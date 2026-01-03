import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

const DB_NAME = 'AppData.db';
const DDL: string[] = [
  // 1) 用户
  `CREATE TABLE IF NOT EXISTS user (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    name TEXT,
    phone TEXT,
    isAdmin INTEGER DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );`,
  `CREATE INDEX IF NOT EXISTS idx_user_account ON user(account);`,

  // 2) 用户画像
  `CREATE TABLE IF NOT EXISTS user_profile (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    age INTEGER,
    gender TEXT,
    height_cm REAL,
    weight_kg REAL,
    body_fat_pct REAL,
    target_steps INTEGER DEFAULT 10000,
    target_calories INTEGER DEFAULT 500,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT,
    FOREIGN KEY(user_id) REFERENCES user(id) ON DELETE CASCADE
  );`,
  `CREATE INDEX IF NOT EXISTS idx_profile_user ON user_profile(user_id);`,

  // 3) 每日健康聚合 (融合原 HealthDatabase 字段命名)
  `CREATE TABLE IF NOT EXISTS health_daily (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    
    -- 运动数据 (Sports)
    steps_current INTEGER DEFAULT 0,
    steps_goal INTEGER DEFAULT 10000,
    steps_distance REAL DEFAULT 0,
    calories_current INTEGER DEFAULT 0,
    calories_goal INTEGER DEFAULT 1200,

    -- 健康数据 (Health)
    sleep_deep REAL DEFAULT 0,
    sleep_light REAL DEFAULT 0,
    sleep_total REAL DEFAULT 0,
    stress_value INTEGER DEFAULT 0,
    heart_rate INTEGER DEFAULT 0,
    bp_systolic INTEGER DEFAULT 0,
    bp_diastolic INTEGER DEFAULT 0,
    spo2 INTEGER DEFAULT 0,
    temperature REAL DEFAULT 0,

    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(user_id, date),
    FOREIGN KEY(user_id) REFERENCES user(id) ON DELETE CASCADE
  );`,
  `CREATE INDEX IF NOT EXISTS idx_health_daily_user_date ON health_daily(user_id, date DESC);`,

  // 4) 健康测量明细
  `CREATE TABLE IF NOT EXISTS health_measurement (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    type TEXT NOT NULL,
    value1 REAL NOT NULL,
    value2 REAL,
    unit TEXT,
    measured_at TEXT NOT NULL,
    FOREIGN KEY(user_id) REFERENCES user(id) ON DELETE CASCADE
  );`,
  `CREATE INDEX IF NOT EXISTS idx_measure_user_type_time ON health_measurement(user_id, type, measured_at DESC);`,

  // 5) 房屋/环境数据
  `CREATE TABLE IF NOT EXISTS house_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    ts TEXT NOT NULL,
    energy_kwh REAL,
    net_up_mbps REAL,
    net_down_mbps REAL,
    light_lux REAL,
    co2_ppm REAL,
    updated_at TEXT,
    FOREIGN KEY(user_id) REFERENCES user(id) ON DELETE CASCADE
  );`,
  `CREATE INDEX IF NOT EXISTS idx_house_user_ts ON house_metrics(user_id, ts DESC);`,

  // 6) 健康宣讲内容
  `CREATE TABLE IF NOT EXISTS health_content (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    doc_url TEXT,
    tags TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );`,

  // 7) 在线问诊医生
  `CREATE TABLE IF NOT EXISTS doctor (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    title TEXT,
    hospital TEXT,
    department TEXT,
    specialty TEXT,
    fee REAL DEFAULT 0,
    intro TEXT,
    priority_base REAL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );`,
  `CREATE INDEX IF NOT EXISTS idx_doctor_dept_priority ON doctor(department, priority_base DESC);`,

  // 8) 推荐日志/缓存
  `CREATE TABLE IF NOT EXISTS recommendation (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    target_type TEXT NOT NULL,
    target_id INTEGER NOT NULL,
    score REAL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(user_id) REFERENCES user(id) ON DELETE CASCADE
  );`,
  `CREATE INDEX IF NOT EXISTS idx_reco_user_type_score ON recommendation(user_id, target_type, score DESC);`
];

export class AppDatabase {
  private static store: relationalStore.RdbStore | null = null;
  private static ctx: Context | null = null;

  static setContext(context: Context) {
    AppDatabase.ctx = context;
  }

  static getStore(): relationalStore.RdbStore | null {
    return AppDatabase.store;
  }

  static async init(context?: Context): Promise<void> {
    if (AppDatabase.store) return;
    if (context) AppDatabase.setContext(context);
    if (!AppDatabase.ctx) {
      console.error('AppDatabase: context 未设置');
      return;
    }

    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    try {
      AppDatabase.store = await relationalStore.getRdbStore(AppDatabase.ctx, config);
      // 逐条执行建表语句
      for (const sql of DDL) {
        await AppDatabase.store.executeSql(sql);
      }
      
      // 尝试添加新字段 (如果表已存在且字段缺失)
      try { await AppDatabase.store.executeSql('ALTER TABLE doctor ADD COLUMN title TEXT'); } catch (e) {}
      try { await AppDatabase.store.executeSql('ALTER TABLE doctor ADD COLUMN specialty TEXT'); } catch (e) {}
      try { await AppDatabase.store.executeSql('ALTER TABLE doctor ADD COLUMN fee REAL DEFAULT 0'); } catch (e) {}

      // ⚡️ 新增：用户目标设置字段
      try { await AppDatabase.store.executeSql('ALTER TABLE user_profile ADD COLUMN target_steps INTEGER DEFAULT 10000'); } catch (e) {}
      try { await AppDatabase.store.executeSql('ALTER TABLE user_profile ADD COLUMN target_calories INTEGER DEFAULT 500'); } catch (e) {}

      // 数据库升级逻辑：尝试添加 isAdmin 字段
      try {
        await AppDatabase.store.executeSql('ALTER TABLE user ADD COLUMN isAdmin INTEGER DEFAULT 0');
        console.info('AppDatabase: 成功添加 isAdmin 字段');
      } catch (e) {
        // 如果字段已存在，会抛出错误，忽略即可
      }

      console.info('AppDatabase: 初始化成功');

      // 检查并创建默认管理员
      await AppDatabase.createDefaultAdmin();
      
      // [调试] 打印数据库内容，方便查看数据是否写入
      // await AppDatabase.dumpToLog(); 

    } catch (err) {
      console.error(`AppDatabase: 初始化失败 - ${JSON.stringify(err)}`);
    }
  }

  // [新增] 调试方法：将数据库内容打印到日志
  static async dumpToLog() {
    if (!AppDatabase.store) return;
    try {
      console.info('=== DATABASE DUMP START ===');
      
      // 1. Dump Users
      let rs = await AppDatabase.store.querySql('SELECT * FROM user');
      console.info(`Table [user]: ${rs.rowCount} rows`);
      while (rs.goToNextRow()) {
        const id = rs.getLong(rs.getColumnIndex('id'));
        const account = rs.getString(rs.getColumnIndex('account'));
        const name = rs.getString(rs.getColumnIndex('name'));
        const isAdmin = rs.getLong(rs.getColumnIndex('isAdmin'));
        console.info(`  User: id=${id}, account=${account}, name=${name}, isAdmin=${isAdmin}`);
      }
      rs.close();

      // 2. Dump Doctors
      rs = await AppDatabase.store.querySql('SELECT * FROM doctor');
      console.info(`Table [doctor]: ${rs.rowCount} rows`);
      while (rs.goToNextRow()) {
        const id = rs.getLong(rs.getColumnIndex('id'));
        const name = rs.getString(rs.getColumnIndex('name'));
        const hospital = rs.getString(rs.getColumnIndex('hospital'));
        console.info(`  Doctor: id=${id}, name=${name}, hospital=${hospital}`);
      }
      rs.close();
      
      console.info('=== DATABASE DUMP END ===');
    } catch (e) {
      console.error('Dump failed:', JSON.stringify(e));
    }
  }

  // 创建默认管理员
  private static async createDefaultAdmin() {
    if (!AppDatabase.store) return;
    try {
      // 检查是否存在 admin 账号
      let predicates = new relationalStore.RdbPredicates('user');
      predicates.equalTo('account', 'admin');
      let rs = await AppDatabase.store.query(predicates);
      
      if (rs.rowCount === 0) {
        console.info('AppDatabase: 创建默认管理员账号 (admin/123456)');
        const valueBucket: relationalStore.ValuesBucket = {
          'account': 'admin',
          'password': '123456', // 实际项目中应加密
          'name': '系统管理员',
          'isAdmin': 1,
          'created_at': new Date().toISOString()
        };
        await AppDatabase.store.insert('user', valueBucket);
        
        // 同时创建画像，避免查询报错
        const userRs = await AppDatabase.store.query(predicates);
        if (userRs.goToFirstRow()) {
           const userId = userRs.getLong(userRs.getColumnIndex('id'));
           const profileValues: relationalStore.ValuesBucket = {
             'user_id': userId,
             'age': 30,
             'gender': 'M',
             'height_cm': 175,
             'weight_kg': 70,
             'created_at': new Date().toISOString()
           };
           await AppDatabase.store.insert('user_profile', profileValues);
        }
        userRs.close();
      }
      rs.close();
    } catch (e) {
      console.error('AppDatabase: 创建默认管理员失败', e);
    }
  }
}