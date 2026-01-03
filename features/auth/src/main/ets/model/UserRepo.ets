import { AppDatabase } from 'utils';
import { relationalStore, ValuesBucket } from '@kit.ArkData';

export interface UserInfo {
  id: number;
  account: string;
  name: string;
  isAdmin: boolean;
}

export interface UserProfile {
  userId: number;
  name: string;
  phone: string;
  height: number;
  weight: number;
  age: number;
  gender: string;
  targetSteps: number;
  targetCalories: number;
}

export class UserRepo {
  // 获取用户详细信息 (User + Profile)
  static async getUserProfile(userId: number): Promise<UserProfile> {
    const store = AppDatabase.getStore();
    if (!store) {
      return {
        userId,
        name: '',
        phone: '',
        height: 0,
        weight: 0,
        age: 0,
        gender: '未知',
        targetSteps: 10000,
        targetCalories: 500
      };
    }
    
    // 1. 查询 User 表
    let userPredicates = new relationalStore.RdbPredicates('user');
    userPredicates.equalTo('id', userId);
    let userRs = await store.query(userPredicates);
    
    let name = '';
    let phone = '';
    
    if (userRs.rowCount > 0) {
      userRs.goToFirstRow();
      name = userRs.getString(userRs.getColumnIndex('name')) || '';
      phone = userRs.getString(userRs.getColumnIndex('phone')) || '';
    }
    userRs.close();

    // 2. 查询 Profile 表
    let profilePredicates = new relationalStore.RdbPredicates('user_profile');
    profilePredicates.equalTo('user_id', userId);
    let profileRs = await store.query(profilePredicates);
    
    let height = 0;
    let weight = 0;
    let age = 0;
    let gender = '未知';
    
    if (profileRs.rowCount > 0) {
      profileRs.goToFirstRow();
      height = profileRs.getDouble(profileRs.getColumnIndex('height_cm')) || 0;
      weight = profileRs.getDouble(profileRs.getColumnIndex('weight_kg')) || 0;
      age = profileRs.getLong(profileRs.getColumnIndex('age')) || 0;
      gender = profileRs.getString(profileRs.getColumnIndex('gender')) || '未知';
    }
    // ⚡️ 读取目标设置 (如果列不存在会返回默认值或0，需处理)
    let targetSteps = 10000;
    let targetCalories = 500;
    try {
        if (profileRs.rowCount > 0) {
            profileRs.goToFirstRow(); // Reset cursor just in case
            const idxSteps = profileRs.getColumnIndex('target_steps');
            const idxCals = profileRs.getColumnIndex('target_calories');
            if (idxSteps !== -1) targetSteps = profileRs.getLong(idxSteps) || 10000;
            if (idxCals !== -1) targetCalories = profileRs.getLong(idxCals) || 500;
        }
    } catch(e) {}
    profileRs.close();

    return {
      userId,
      name,
      phone,
      height,
      weight,
      age,
      gender,
      targetSteps,
      targetCalories
    };
  }

  // 更新用户信息
  static async updateUserProfile(profile: UserProfile): Promise<boolean> {
    const store = AppDatabase.getStore();
    if (!store) return false;
    
    try {
      // 1. 更新 User 表
      const userValues: ValuesBucket = {
        'name': profile.name,
        'phone': profile.phone
      };
      let userPredicates = new relationalStore.RdbPredicates('user');
      userPredicates.equalTo('id', profile.userId);
      await store.update(userValues, userPredicates);

      // 2. 更新或插入 Profile 表
      // 先检查是否存在
      let profilePredicates = new relationalStore.RdbPredicates('user_profile');
      profilePredicates.equalTo('user_id', profile.userId);
      let rs = await store.query(profilePredicates);
      
      const profileValues: ValuesBucket = {
        'height_cm': profile.height,
        'weight_kg': profile.weight,
        'age': profile.age,
        'gender': profile.gender,
        'target_steps': profile.targetSteps,
        'target_calories': profile.targetCalories,
        'updated_at': new Date().toISOString()
      };

      if (rs.rowCount > 0) {
        // 更新
        await store.update(profileValues, profilePredicates);
      } else {
        // 插入
        profileValues['user_id'] = profile.userId;
        await store.insert('user_profile', profileValues);
      }
      rs.close();

      // ⚡️ 同步更新今日的 health_daily 目标
      const today = new Date();
      const year = today.getFullYear();
      const month = (today.getMonth() + 1).toString().padStart(2, '0');
      const day = today.getDate().toString().padStart(2, '0');
      const dateStr = `${year}-${month}-${day}`;

      // 尝试更新今日记录 (如果存在)
      const healthValues: ValuesBucket = {
        'steps_goal': profile.targetSteps,
        'calories_goal': profile.targetCalories,
        'updated_at': new Date().toISOString()
      };
      let healthPredicates = new relationalStore.RdbPredicates('health_daily');
      healthPredicates.equalTo('user_id', profile.userId);
      healthPredicates.equalTo('date', dateStr);
      await store.update(healthValues, healthPredicates);
      
      return true;
    } catch (e) {
      console.error('Update profile failed:', e);
      return false;
    }
  }

  // 注册
  static async register(account: string, password: string): Promise<boolean> {
    const store = AppDatabase.getStore();
    if (!store) return false;
    // 1. 查重
    let predicates = new relationalStore.RdbPredicates('user');
    predicates.equalTo('account', account);
    let resultSet = await store.query(predicates);
    if (resultSet.rowCount > 0) {
      resultSet.close();
      return false;
    }
    resultSet.close();

    // 2. 插入
    const valueBucket: ValuesBucket = {
      'account': account,
      'password': password,
      'name': '用户' + Math.floor(Math.random() * 1000)
    };
    await store.insert('user', valueBucket);
    return true;
  }

  // 登录
  static async login(account: string, password: string): Promise<UserInfo | null> {
    const store = AppDatabase.getStore();
    if (!store) return null;
    let predicates = new relationalStore.RdbPredicates('user');
    predicates.equalTo('account', account);
    predicates.equalTo('password', password);

    let resultSet = await store.query(predicates);
    let result: UserInfo | null = null;

    if (resultSet.rowCount > 0) {
      resultSet.goToFirstRow();
      const isAdminVal = resultSet.getLong(resultSet.getColumnIndex('isAdmin'));
      result = {
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        account: resultSet.getString(resultSet.getColumnIndex('account')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        isAdmin: isAdminVal === 1
      };
    }
    resultSet.close();
    return result;
  }

  // 设置用户为管理员
  static async setAdmin(account: string, isAdmin: boolean): Promise<boolean> {
    const store = AppDatabase.getStore();
    if (!store) return false;
    const values: ValuesBucket = {
      'isAdmin': isAdmin ? 1 : 0
    };
    let predicates = new relationalStore.RdbPredicates('user');
    predicates.equalTo('account', account);
    
    try {
      const rows = await store.update(values, predicates);
      return rows > 0;
    } catch (e) {
      console.error('Set admin failed:', e);
      return false;
    }
  }
}