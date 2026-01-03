import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from 'utils';
import { Context } from '@kit.AbilityKit';
import { AppStorageV2 } from '@kit.ArkUI';

// 用户信息类（用于AppStorageV2）
class UserInfo {
  id: number = 0;
  account: string = '';
  name: string = '';
  isAdmin: boolean = false;

  constructor() {}
}

export class UserGoals {
  steps: number = 10000;
  calories: number = 500;
}

// 健康数据结构
export class HealthRecord {
  id: number = 0;
  userId: number = 1; // 绑定到当前登录用户
  date: string = ''; // YYYY-MM-DD格式

  // 运动数据
  stepsCurrent: number = 0;
  stepsGoal: number = 10000;
  stepsDistance: number = 0;
  caloriesCurrent: number = 0;
  caloriesGoal: number = 1200;

  // 健康数据
  sleepDeep: number = 0;
  sleepLight: number = 0;
  sleepTotal: number = 0;
  stressValue: number = 0;
  heartRate: number = 0;
  bpSystolic: number = 0;
  bpDiastolic: number = 0;
  spo2: number = 0;
  temperature: number = 0;

  createdAt: string = '';
  updatedAt: string = '';

  constructor() {}

  initialize(date: string, userId: number): void {
    this.date = date;
    this.userId = userId;
  }
}

// AI建议响应结构
export class AIAdviceResponse {
  advice: string = '';
  riskLevel: 'low' | 'medium' | 'high' = 'low';
  recommendations: string[] = [];
  timestamp: string = '';

  constructor() {}

  initialize(advice: string, riskLevel: 'low' | 'medium' | 'high', recommendations: string[]): void {
    this.advice = advice;
    this.riskLevel = riskLevel;
    this.recommendations = recommendations;
    this.timestamp = new Date().toISOString();
  }
}

// HTTP请求参数结构
export class HttpRequestOptions {
  url: string = '';
  method: string = 'GET';
  headers: Record<string, string> = {};
  body: string = '';

  constructor() {}

  initialize(url: string, method: string, headers: Record<string, string>, body: string): void {
    this.url = url;
    this.method = method;
    this.headers = headers;
    this.body = body;
  }
}

// HTTP响应结构
export class HttpResponse {
  result: string = '';
  statusCode: number = 0;

  constructor() {}
}

// 趋势分析结果
export class TrendAnalysisResult {
  period: string = '';
  stepTrend: 'up' | 'down' | 'stable' = 'stable';
  sleepTrend: 'up' | 'down' | 'stable' = 'stable';
  stressTrend: 'up' | 'down' | 'stable' = 'stable';
  improvementSuggestions: string[] = [];

  constructor() {}
}

// DeepSeek API相关接口
export interface DeepSeekMessage {
  content: string;
}

export interface DeepSeekChoice {
  message: DeepSeekMessage;
}

export interface DeepSeekAPIResponse {
  choices: DeepSeekChoice[];
}

export interface AIAnalysisResult {
  advice: string;
  riskLevel: 'low' | 'medium' | 'high';
  recommendations: string[];
}

export class HealthDataService {
  private static isInitialized: boolean = false;
  private static currentUserId: number = 1; // 当前登录用户ID

  // 初始化服务
  static async init(context: Context): Promise<void> {
    if (!HealthDataService.isInitialized) {
      try {
        await AppDatabase.init(context);
        HealthDataService.isInitialized = true;

        console.info('HealthDataService: 初始化成功');
      } catch (error) {
        console.error('HealthDataService: 初始化失败', error);
        throw new Error(String(error));
      }
    }

    // 获取当前登录用户ID
    HealthDataService.setCurrentUserId();
  }

  // 设置当前登录用户ID（从AppStorage获取）
  static setCurrentUserId(): void {
    try {
      // 先尝试从AppStorage获取当前用户ID（LoginPage使用AppStorage存储）
      const authUser: Record<string, Object> | undefined = AppStorage.get('currentUser');
      if (authUser) {
        const userId = authUser['id'] as number;
        if (userId > 0) {
          HealthDataService.currentUserId = userId;
          console.info('HealthDataService: 从AppStorage加载用户ID', userId);
          return;
        }
      }

      // 如果AppStorage中没有，再尝试从AppStorageV2获取
      const currentUser = AppStorageV2.connect(UserInfo, 'currentUser', () => new UserInfo());
      if (currentUser && currentUser.id > 0) {
        HealthDataService.currentUserId = currentUser.id;
        console.info('HealthDataService: 从AppStorageV2加载用户ID', currentUser.id);
      } else {
        HealthDataService.currentUserId = 1;
        console.warn('HealthDataService: AppStorage用户ID无效，使用默认值1');
      }
    } catch (error) {
      console.error('HealthDataService: 获取用户ID失败', error);
      HealthDataService.currentUserId = 1;
    }
  }

  // 设置当前登录用户ID（由外部调用，在用户登录后设置）
  static setCurrentUserIdValue(userId: number): void {
    if (userId > 0) {
      HealthDataService.currentUserId = userId;
      console.info('HealthDataService: 当前用户ID设置为', userId);
    } else {
      console.warn('HealthDataService: 用户ID无效，使用默认值1');
      HealthDataService.currentUserId = 1;
    }
  }

  // 获取当前登录用户ID
  static getCurrentUserId(): number {
    return HealthDataService.currentUserId;
  }

  // 更新当前登录用户ID（用于切换用户）
  static updateCurrentUserId(userId: number): void {
    HealthDataService.setCurrentUserIdValue(userId);
  }

  // 格式化日期为 YYYY-MM-DD
  public static formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  // 保持原有接口函数名 - 获取今日运动数据
  static async getLatestSportsData(): Promise<HealthRecord | null> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return null;
      }
      const predicates = new relationalStore.RdbPredicates('health_daily');
      predicates.equalTo('user_id', HealthDataService.currentUserId);
      predicates.orderByDesc('date');
      predicates.limitAs(1);

      const resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        const record = HealthDataService.resultSetToHealthRecord(resultSet);
        resultSet.close();
        return record;
      }
      resultSet.close();
      return null;
    } catch (error) {
      console.error('HealthDataService: 获取运动数据失败', error);
      throw new Error(`获取运动数据失败: ${JSON.stringify(error)}`);
    }
  }

  // 保持原有接口函数名 - 获取今日健康数据
  static async getLatestHealthData(): Promise<HealthRecord | null> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return null;
      }
      const predicates = new relationalStore.RdbPredicates('health_daily');
      predicates.equalTo('user_id', HealthDataService.currentUserId);
      predicates.orderByDesc('date');
      predicates.limitAs(1);

      const resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        const record = HealthDataService.resultSetToHealthRecord(resultSet);
        resultSet.close();
        return record;
      }
      resultSet.close();
      return null;
    } catch (error) {
      console.error('HealthDataService: 获取健康数据失败', error);
      throw new Error(String(error));
    }
  }

  // ⚡️ 内部辅助：获取用户配置的目标
  private static async getUserProfileGoals(userId: number): Promise<UserGoals | null> {
    try {
      const store = AppDatabase.getStore();
      if (!store) return null;
      
      const predicates = new relationalStore.RdbPredicates('user_profile');
      predicates.equalTo('user_id', userId);
      const rs = await store.query(predicates);
      
      let result: UserGoals | null = null;
      if (rs.goToFirstRow()) {
        const idxSteps = rs.getColumnIndex('target_steps');
        const idxCals = rs.getColumnIndex('target_calories');
        if (idxSteps !== -1 && idxCals !== -1) {
            result = new UserGoals();
            result.steps = rs.getLong(idxSteps) || 10000;
            result.calories = rs.getLong(idxCals) || 500;
        }
      }
      rs.close();
      return result;
    } catch (e) {
      return null;
    }
  }

  // 保持原有接口函数名 - 保存运动数据
  static async saveSportsData(data: HealthRecord): Promise<void> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return;
      }

      // 确保数据绑定到当前登录用户
      data.userId = HealthDataService.currentUserId;
      const valueBucket = HealthDataService.healthRecordToValuesBucket(data);

      // 先查询是否存在该日期的记录
      const existing = await HealthDataService.getHealthDataByDate(data.date);

      if (existing) {
        // 更新现有记录
        const predicates = new relationalStore.RdbPredicates('health_daily');
        predicates.equalTo('user_id', HealthDataService.currentUserId);
        predicates.equalTo('date', data.date);
        await store.update(valueBucket, predicates);
        console.info(`HealthDataService: 用户${HealthDataService.currentUserId}的运动数据更新成功`);
      } else {
        // ⚡️ 插入新记录前，尝试应用用户设定的全局目标
        // 只有当传入的目标值是默认值时才覆盖，避免覆盖用户手动修改的单日目标
        // (这里简化处理：如果是新插入，优先使用全局配置)
        const profileGoals = await HealthDataService.getUserProfileGoals(HealthDataService.currentUserId);
        if (profileGoals) {
            valueBucket['steps_goal'] = profileGoals.steps;
            valueBucket['calories_goal'] = profileGoals.calories;
        }

        // 插入新记录
        await store.insert('health_daily', valueBucket);
        console.info(`HealthDataService: 用户${HealthDataService.currentUserId}的运动数据保存成功`);
      }
    } catch (error) {
      console.error('HealthDataService: 保存运动数据失败', error);
      throw new Error(`保存运动数据失败: ${JSON.stringify(error)}`);
    }
  }

  // ⚡️ 新增：更新每日目标
  static async updateDailyGoals(date: string, stepsGoal: number, caloriesGoal: number): Promise<void> {
    try {
      HealthDataService.ensureInitialized();
      const store = AppDatabase.getStore();
      if (!store) return;

      const userId = HealthDataService.currentUserId;
      
      // 检查是否存在记录
      const existing = await HealthDataService.getHealthDataByDate(date);
      
      if (existing) {
        const values: relationalStore.ValuesBucket = {
          'steps_goal': stepsGoal,
          'calories_goal': caloriesGoal,
          'updated_at': new Date().toISOString()
        };
        const predicates = new relationalStore.RdbPredicates('health_daily');
        predicates.equalTo('user_id', userId);
        predicates.equalTo('date', date);
        await store.update(values, predicates);
      } else {
        // 如果不存在，创建一个新的，但需要注意其他字段默认为0
        const values: relationalStore.ValuesBucket = {
          'user_id': userId,
          'date': date,
          'steps_goal': stepsGoal,
          'calories_goal': caloriesGoal,
          'updated_at': new Date().toISOString()
        };
        await store.insert('health_daily', values);
      }
      console.info(`HealthDataService: Updated goals for user ${userId} on ${date}`);
    } catch (e) {
      console.error('HealthDataService: updateDailyGoals failed', e);
    }
  }

  // 保持原有接口函数名 - 保存健康数据
  static async saveHealthData(data: HealthRecord): Promise<void> {
    try {
      // 确保数据绑定到当前登录用户
      data.userId = HealthDataService.currentUserId;
      return await HealthDataService.saveSportsData(data); // 统一处理
    } catch (error) {
      console.error('HealthDataService: 保存健康数据失败', error);
      throw new Error(String(error));
    }
  }

  // 新增接口 - 根据日期获取健康数据
  static async getHealthDataByDate(date: string): Promise<HealthRecord | null> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return null;
      }
      const predicates = new relationalStore.RdbPredicates('health_daily');
      predicates.equalTo('user_id', HealthDataService.currentUserId);
      predicates.equalTo('date', date);

      const resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        const record = HealthDataService.resultSetToHealthRecord(resultSet);
        resultSet.close();
        return record;
      }
      resultSet.close();
      return null;
    } catch (error) {
      console.error('HealthDataService: 查询健康数据失败', error);
      throw new Error(`查询健康数据失败: ${JSON.stringify(error)}`);
    }
  }

  // 新增接口 - 获取日期范围内的健康数据
  static async getHealthDataByDateRange(startDate: string, endDate: string): Promise<HealthRecord[]> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return [];
      }
      const predicates = new relationalStore.RdbPredicates('health_daily');
      predicates.equalTo('user_id', HealthDataService.currentUserId);
      predicates.between('date', startDate, endDate);
      predicates.orderByAsc('date');

      const resultSet = await store.query(predicates);
      const records: HealthRecord[] = [];

      while (resultSet.goToNextRow()) {
        records.push(HealthDataService.resultSetToHealthRecord(resultSet));
      }
      resultSet.close();
      return records;
    } catch (error) {
      console.error('HealthDataService: 查询日期范围健康数据失败', error);
      throw new Error(`查询日期范围健康数据失败: ${JSON.stringify(error)}`);
    }
  }

  // 新增接口 - 删除健康数据
  static async deleteHealthData(date: string): Promise<void> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return;
      }
      const predicates = new relationalStore.RdbPredicates('health_daily');
      predicates.equalTo('user_id', HealthDataService.currentUserId);
      predicates.equalTo('date', date);

      const result = await store.delete(predicates);
      console.info(`HealthDataService: 用户${HealthDataService.currentUserId}删除健康数据成功，影响行数: ${result}`);
    } catch (error) {
      console.error('HealthDataService: 删除健康数据失败', error);
      throw new Error(`删除健康数据失败: ${JSON.stringify(error)}`);
    }
  }

  // 新增接口 - 批量保存健康数据（支持多个指标同时更新）
  static async batchSaveHealthData(records: HealthRecord[]): Promise<void> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return;
      }

      store.beginTransaction();

      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        // 确保所有记录都绑定到当前登录用户
        record.userId = HealthDataService.currentUserId;
        const valueBucket = HealthDataService.healthRecordToValuesBucket(record);
        const existing = await HealthDataService.getHealthDataByDate(record.date);

        if (existing) {
          const predicates = new relationalStore.RdbPredicates('health_daily');
          predicates.equalTo('user_id', HealthDataService.currentUserId);
          predicates.equalTo('date', record.date);
          await store.update(valueBucket, predicates);
        } else {
          await store.insert('health_daily', valueBucket);
        }
      }

      store.commit();
      console.info(`HealthDataService: 用户${HealthDataService.currentUserId}批量保存健康数据成功，共${records.length}条记录`);
    } catch (error) {
      const store = AppDatabase.getStore();
      if (store) {
        await store.rollback(0);
      }
      console.error('HealthDataService: 批量保存健康数据失败', error);
      throw new Error(`批量保存健康数据失败: ${JSON.stringify(error)}`);
    }

  }

  // 新增接口 - 获取AI健康建议
  static async getAIAdvice(): Promise<AIAdviceResponse> {
    try {
      HealthDataService.ensureInitialized();

      // 获取最近30天的健康数据
      const endDate = HealthDataService.formatDate(new Date());
      const startDateObj = new Date();
      startDateObj.setDate(startDateObj.getDate() - 30);
      const startDate = HealthDataService.formatDate(startDateObj);

      const healthRecords = await HealthDataService.getHealthDataByDateRange(startDate, endDate);

      const response = new AIAdviceResponse();

      if (healthRecords.length === 0) {
        response.initialize(
          '暂无足够的健康数据进行智能分析，建议您先记录一些健康数据。',
          'low',
          ['开始记录每日步数', '记录睡眠质量', '关注心率变化']
        );
        return response;
      }

      // 调用DeepSeek API进行分析
      const aiResponse = await HealthDataService.callDeepSeekAPI(healthRecords);
      return aiResponse;

    } catch (error) {
      console.error('HealthDataService: 获取AI建议失败', error);

      // 返回默认建议
      const response = new AIAdviceResponse();
      response.initialize(
        '无法获取AI分析建议，请检查网络连接或稍后重试。',
        'medium',
        ['检查网络连接', '重试获取建议', '查看历史数据']
      );
      return response;
    }
  }

  // 调用DeepSeek API
  private static async callDeepSeekAPI(healthRecords: HealthRecord[]): Promise<AIAdviceResponse> {
    // 构建分析数据
    const analysisData = HealthDataService.prepareAnalysisData(healthRecords);

    const prompt = '作为一个专业的健康分析师，请基于以下30天的健康数据给出智能建议：\n\n数据概览：\n' + analysisData + '\n\n请从以下角度进行分析：\n1. 运动习惯分析（步数、卡路里消耗趋势）\n2. 睡眠质量评估（深度睡眠和浅度睡眠比例）\n3. 心血管健康（心率、血压趋势）\n4. 压力状态评估\n5. 体温和血氧监测\n\n请提供：\n- 整体健康状况评估\n- 具体的改进建议\n- 风险预警（如有）\n\n请以JSON格式回复：\n{\n  "advice": "详细分析和建议",\n  "riskLevel": "low/medium/high",\n  "recommendations": ["具体建议1", "具体建议2", "具体建议3"]\n}';

    try {
      // 构建HTTP请求头
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer YOUR_DEEPSEEK_API_KEY' // 需要用户提供API密钥
      };

      // 构建请求体
      interface DeepSeekMessage {
        role: string;
        content: string;
      }

      interface DeepSeekRequestBody {
        model: string;
        messages: DeepSeekMessage[];
        max_tokens: number;
        temperature: number;
      }

      const message: DeepSeekMessage = {
        role: 'user',
        content: prompt
      };

      const messages: DeepSeekMessage[] = [message];

      const requestBody: DeepSeekRequestBody = {
        model: 'deepseek-chat',
        messages: messages,
        max_tokens: 1000,
        temperature: 0.7
      };

      const requestOptions = new HttpRequestOptions();
      requestOptions.initialize(
        'https://api.deepseek.com/v1/chat/completions',
        'POST',
        headers,
        JSON.stringify(requestBody)
      );

      const response = await HealthDataService.httpRequest(requestOptions);

      const aiResult: DeepSeekAPIResponse = JSON.parse(response) as DeepSeekAPIResponse;
      const content: string = aiResult.choices[0].message.content;
      const parsed: AIAnalysisResult = JSON.parse(content) as AIAnalysisResult;

      const result = new AIAdviceResponse();
      result.initialize(
        parsed.advice,
        parsed.riskLevel,
        parsed.recommendations
      );
      return result;

    } catch (error) {
      console.error('DeepSeek API调用失败', error);

      // 返回基于规则的默认分析
      return HealthDataService.generateDefaultAnalysis(healthRecords);
    }
  }

  // 准备分析数据
  private static prepareAnalysisData(healthRecords: HealthRecord[]): string {
    if (healthRecords.length === 0) {
      return '暂无数据';
    }

    const totalDays = healthRecords.length;
    let sumSteps = 0;
    let sumCalories = 0;
    let sumSleep = 0;
    let sumHeartRate = 0;
    let sumStress = 0;
    let sumTemp = 0;

    for (let i = 0; i < healthRecords.length; i++) {
      const record = healthRecords[i];
      sumSteps += record.stepsCurrent;
      sumCalories += record.caloriesCurrent;
      sumSleep += record.sleepTotal;
      sumHeartRate += record.heartRate;
      sumStress += record.stressValue;
      sumTemp += record.temperature;
    }

    const avgSteps = sumSteps / totalDays;
    const avgCalories = sumCalories / totalDays;
    const avgSleep = sumSleep / totalDays;
    const avgHeartRate = sumHeartRate / totalDays;
    const avgStress = sumStress / totalDays;
    const avgTemp = sumTemp / totalDays;

    let result = '记录天数: ' + totalDays + '天\n';
    result += '平均步数: ' + Math.round(avgSteps) + '步\n';
    result += '平均卡路里: ' + Math.round(avgCalories) + '卡\n';
    result += '平均睡眠: ' + avgSleep.toFixed(1) + '小时\n';
    result += '平均心率: ' + Math.round(avgHeartRate) + '次/分\n';
    result += '平均压力值: ' + Math.round(avgStress) + '\n';
    result += '平均体温: ' + avgTemp.toFixed(1) + '°C\n\n';
    result += '数据详情:\n';

    for (let i = 0; i < healthRecords.length; i++) {
      const record = healthRecords[i];
      result += record.date + ': 步数' + record.stepsCurrent +
        ', 卡路里' + record.caloriesCurrent +
        ', 睡眠' + record.sleepTotal + 'h, ' +
        '心率' + record.heartRate +
        ', 压力' + record.stressValue;
      if (i < healthRecords.length - 1) {
        result += '\n';
      }
    }

    return result;
  }

  // 生成默认分析（当AI API调用失败时）
  private static generateDefaultAnalysis(healthRecords: HealthRecord[]): AIAdviceResponse {
    const totalDays = healthRecords.length;

    let sumSteps = 0;
    let sumSleep = 0;
    let sumHeartRate = 0;
    let sumStress = 0;

    for (let i = 0; i < healthRecords.length; i++) {
      const record = healthRecords[i];
      sumSteps += record.stepsCurrent;
      sumSleep += record.sleepTotal;
      sumHeartRate += record.heartRate;
      sumStress += record.stressValue;
    }

    const avgSteps = sumSteps / totalDays;
    const avgSleep = sumSleep / totalDays;
    const avgHeartRate = sumHeartRate / totalDays;
    const avgStress = sumStress / totalDays;

    let advice = '根据最近' + totalDays + '天的健康数据分析：\n\n';
    let riskLevel: 'low' | 'medium' | 'high' = 'low';
    const recommendations: string[] = [];

    // 步数分析
    if (avgSteps < 5000) {
      advice += '• 您的日均步数偏低，建议增加日常活动量。\n';
      recommendations.push('每天至少步行8000步');
    } else if (avgSteps >= 8000) {
      advice += '• 您的运动量很好，继续保持！\n';
    }

    // 睡眠分析
    if (avgSleep < 7) {
      advice += '• 睡眠时间不足，建议保证7-8小时睡眠。\n';
      recommendations.push('规律作息时间');
    } else if (avgSleep > 9) {
      advice += '• 睡眠时间较长，注意睡眠质量。\n';
    }

    // 心率分析
    if (avgHeartRate > 100) {
      advice += '• 平均心率偏高，建议关注心血管健康。\n';
      riskLevel = 'medium';
      recommendations.push('适当进行有氧运动');
    }

    // 压力分析
    if (avgStress > 70) {
      advice += '• 压力水平较高，建议进行放松活动。\n';
      recommendations.push('练习深呼吸或冥想');
    }

    if (recommendations.length === 0) {
      recommendations.push('继续保持良好的生活习惯');
    }

    const result = new AIAdviceResponse();
    result.initialize(advice.trim(), riskLevel, recommendations);
    return result;
  }

  // HTTP请求工具方法
  private static async httpRequest(options: HttpRequestOptions): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      try {
        const httpModule = import('@kit.ArkTS');
        httpModule.then((module: Object) => {
          const http = (module as Record<string, Object>).http as Record<string, Object>;
          const createHttp = http.createHttp as () => Record<string, Object>;
          const request = createHttp();

          interface HttpRequestParams {
            method: string;
            header: Record<string, string>;
            extraData: string;
          }

          const params: HttpRequestParams = {
            method: options.method,
            header: options.headers,
            extraData: options.body
          };

          const requestMethod = request.request as (url: string, params: HttpRequestParams, callback: (err: Error | null, data: HttpResponse) => void) => void;
          requestMethod(options.url, params, (err: Error | null, data: HttpResponse) => {
            if (err) {
              reject(err);
            } else {
              resolve(data.result);
            }
          });
        }).catch((error: Error) => {
          reject(error);
        });
      } catch (error) {
        reject(new Error(String(error)));
      }
    });
  }

  // 辅助方法：ResultSet转换为HealthRecord
  private static resultSetToHealthRecord(resultSet: relationalStore.ResultSet): HealthRecord {
    try {
      const record = new HealthRecord();

      // 使用安全获取方法，防止列不存在导致崩溃
      const safeGetLong = (colName: string): number => {
        const idx = resultSet.getColumnIndex(colName);
        if (idx !== -1 && !resultSet.isColumnNull(idx)) {
          return resultSet.getLong(idx);
        }
        return 0;
      };
      
      const safeGetDouble = (colName: string): number => {
        const idx = resultSet.getColumnIndex(colName);
        if (idx !== -1 && !resultSet.isColumnNull(idx)) {
          return resultSet.getDouble(idx);
        }
        return 0.0;
      };

      const safeGetString = (colName: string): string => {
        const idx = resultSet.getColumnIndex(colName);
        if (idx !== -1 && !resultSet.isColumnNull(idx)) {
          return resultSet.getString(idx);
        }
        return '';
      };

      record.id = safeGetLong('id');
      record.userId = safeGetLong('user_id');
      record.date = safeGetString('date');

      record.stepsCurrent = safeGetLong('steps_current');
      record.stepsGoal = safeGetLong('steps_goal');
      record.stepsDistance = safeGetDouble('steps_distance');
      record.caloriesCurrent = safeGetLong('calories_current');
      record.caloriesGoal = safeGetLong('calories_goal');

      record.sleepDeep = safeGetDouble('sleep_deep');
      record.sleepLight = safeGetDouble('sleep_light');
      record.sleepTotal = safeGetDouble('sleep_total');
      record.stressValue = safeGetLong('stress_value');
      record.heartRate = safeGetLong('heart_rate');
      record.bpSystolic = safeGetLong('bp_systolic');
      record.bpDiastolic = safeGetLong('bp_diastolic');
      record.spo2 = safeGetLong('spo2');
      record.temperature = safeGetDouble('temperature');

      record.createdAt = safeGetString('created_at');
      record.updatedAt = safeGetString('updated_at');

      return record;
    } catch (error) {
      console.error('HealthDataService: ResultSet转换失败', error);
      throw new Error(String(error));
    }
  }

  // 辅助方法：HealthRecord转换为ValuesBucket
  private static healthRecordToValuesBucket(record: HealthRecord): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {};

    bucket.user_id = record.userId;
    bucket.date = record.date;

    // 运动数据
    bucket.steps_current = record.stepsCurrent;
    bucket.steps_goal = record.stepsGoal;
    bucket.steps_distance = record.stepsDistance;
    bucket.calories_current = record.caloriesCurrent;
    bucket.calories_goal = record.caloriesGoal;

    // 健康数据
    bucket.sleep_deep = record.sleepDeep;
    bucket.sleep_light = record.sleepLight;
    bucket.sleep_total = record.sleepTotal;
    bucket.stress_value = record.stressValue;
    bucket.heart_rate = record.heartRate;
    bucket.bp_systolic = record.bpSystolic;
    bucket.bp_diastolic = record.bpDiastolic;
    bucket.spo2 = record.spo2;
    bucket.temperature = record.temperature;

    bucket.updated_at = new Date().toISOString();

    return bucket;
  }

  // 确保服务已初始化
  private static ensureInitialized(): void {
    if (!HealthDataService.isInitialized) {
      throw new Error('HealthDataService 未初始化，请先调用 HealthDataService.init(context)');
    }
  }

  // 模拟数据更新 (新增)
  static async simulateData(userId?: number): Promise<void> {
    try {
      if (userId !== undefined) {
        HealthDataService.currentUserId = userId;
      }
      HealthDataService.ensureInitialized();
      
      // 1. 获取今日数据
      const todayStr = HealthDataService.formatDate(new Date());
      let record = await HealthDataService.getHealthDataByDate(todayStr);
      
      if (record) {
        // 2. 模拟步数增加
        const addedSteps = Math.floor(Math.random() * 500) + 100;
        record.stepsCurrent += addedSteps;
        record.stepsDistance += (addedSteps * 0.7 / 1000); // 粗略计算
        record.caloriesCurrent += Math.floor(addedSteps * 0.04);
        
        // 3. 模拟心率/体温/血氧/压力/血压波动
        record.heartRate = Math.floor(Math.random() * (100 - 60) + 60);
        record.temperature = parseFloat((36.0 + Math.random()).toFixed(1));
        record.spo2 = Math.floor(Math.random() * (100 - 95) + 95); // 95-99%
        record.stressValue = Math.floor(Math.random() * 60 + 20); // 20-80
        record.bpSystolic = Math.floor(Math.random() * (130 - 110) + 110); // 110-130
        record.bpDiastolic = Math.floor(Math.random() * (85 - 70) + 70); // 70-85
        record.updatedAt = new Date().toISOString();
        
        // 4. 更新数据库
        await HealthDataService.saveHealthData(record);
        console.info('HealthDataService: 模拟数据更新成功');
      } else {
        // 如果没有今日数据，创建一个新的
        const newRecord = new HealthRecord();
        newRecord.initialize(todayStr, HealthDataService.currentUserId);
        newRecord.stepsCurrent = 1000;
        newRecord.sleepTotal = 7.0; // 假设昨晚睡了7小时
        
        // 初始化基础健康数据
        newRecord.heartRate = Math.floor(Math.random() * (100 - 60) + 60);
        newRecord.temperature = parseFloat((36.0 + Math.random()).toFixed(1));
        newRecord.spo2 = Math.floor(Math.random() * (100 - 95) + 95);
        newRecord.stressValue = Math.floor(Math.random() * 60 + 20);
        newRecord.bpSystolic = Math.floor(Math.random() * (130 - 110) + 110);
        newRecord.bpDiastolic = Math.floor(Math.random() * (85 - 70) + 70);
        
        await HealthDataService.saveHealthData(newRecord);
        console.info('HealthDataService: 模拟数据创建成功');
      }
    } catch (error) {
       console.error('HealthDataService: 模拟数据失败', JSON.stringify(error));
    }
  }

  // 新增接口 - 清空当前用户所有健康数据（用于测试）
  static async clearAllData(): Promise<void> {
    try {
      HealthDataService.ensureInitialized();

      const store = AppDatabase.getStore();
      if (!store) {
        console.error('HealthDataService: Database store is null');
        return;
      }
      const predicates = new relationalStore.RdbPredicates('health_daily');
      predicates.equalTo('user_id', HealthDataService.currentUserId);

      await store.delete(predicates);
      console.info(`HealthDataService: 用户${HealthDataService.currentUserId}清空健康数据成功`);
    } catch (error) {
      console.error('HealthDataService: 清空健康数据失败', error);
      throw new Error(`清空健康数据失败: ${JSON.stringify(error)}`);
    }
  }
}