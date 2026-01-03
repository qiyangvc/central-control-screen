import { Context } from '@kit.AbilityKit';
import { TodaySportsData, HealthData, DatabaseResult } from '../model/SportsDataModel';
import { HealthDataService, HealthRecord, AIAdviceResponse } from '../database/HealthDataService';

export class HealthSportsViewModel {
  constructor() {}

  // 初始化视图模型
  static async init(context: Context): Promise<void> {
    await HealthDataService.init(context);
  }

  async getTodaySports(): Promise<TodaySportsData> {
    const today = HealthDataService.formatDate(new Date());
    const record = await HealthDataService.getHealthDataByDate(today);
    const result = new TodaySportsData();

    if (record) {
      result.steps.current = record.stepsCurrent;
      result.steps.goal = record.stepsGoal;
      result.steps.distance = record.stepsDistance;
      result.calories.current = record.caloriesCurrent;
      result.calories.goal = record.caloriesGoal;
    }

    return result;
  }

  async getHealthData(): Promise<HealthData> {
    const today = HealthDataService.formatDate(new Date());
    const record = await HealthDataService.getHealthDataByDate(today);
    const result = new HealthData();

    if (record) {
      result.sleep.deepSleep = record.sleepDeep;
      result.sleep.lightSleep = record.sleepLight;
      result.sleep.totalSleep = record.sleepTotal;
      result.sleep.date = record.date;
      result.stress.value = record.stressValue;
      result.stress.date = record.date;
      result.heart.heartRate = record.heartRate;
      result.heart.date = record.date;
      result.bloodPressure.systolic = record.bpSystolic;
      result.bloodPressure.diastolic = record.bpDiastolic;
      result.bloodPressure.date = record.date;
      result.bloodOxygen.spo2 = record.spo2;
      result.bloodOxygen.date = record.date;
      result.temperature.value = record.temperature;
      result.temperature.date = record.date;
    }

    return result;
  }

  async loadDataFromDatabase(): Promise<DatabaseResult> {
    try {
      const today = HealthDataService.formatDate(new Date());
      const sportsRecord = await HealthDataService.getHealthDataByDate(today);
      const healthRecord = await HealthDataService.getHealthDataByDate(today);
      console.info('从数据库加载数据成功');

      const result = new DatabaseResult();

      if (sportsRecord) {
        const sportsData = new TodaySportsData();
        sportsData.steps.current = sportsRecord.stepsCurrent;
        sportsData.steps.goal = sportsRecord.stepsGoal;
        sportsData.steps.distance = sportsRecord.stepsDistance;
        sportsData.calories.current = sportsRecord.caloriesCurrent;
        sportsData.calories.goal = sportsRecord.caloriesGoal;
        result.sports = sportsData;
      } else {
        result.sports = null;
      }

      if (healthRecord) {
        const healthData = new HealthData();
        healthData.sleep.deepSleep = healthRecord.sleepDeep;
        healthData.sleep.lightSleep = healthRecord.sleepLight;
        healthData.sleep.totalSleep = healthRecord.sleepTotal;
        healthData.sleep.date = healthRecord.date;
        healthData.stress.value = healthRecord.stressValue;
        healthData.stress.date = healthRecord.date;
        healthData.heart.heartRate = healthRecord.heartRate;
        healthData.heart.date = healthRecord.date;
        healthData.bloodPressure.systolic = healthRecord.bpSystolic;
        healthData.bloodPressure.diastolic = healthRecord.bpDiastolic;
        healthData.bloodPressure.date = healthRecord.date;
        healthData.bloodOxygen.spo2 = healthRecord.spo2;
        healthData.bloodOxygen.date = healthRecord.date;
        healthData.temperature.value = healthRecord.temperature;
        healthData.temperature.date = healthRecord.date;
        result.health = healthData;
      } else {
        result.health = null;
      }

      return result;
    } catch (error) {
      console.error(`从数据库加载数据失败: ${JSON.stringify(error)}`);
      const result = new DatabaseResult();
      result.sports = null;
      result.health = null;
      return result;
    }
  }

  async syncDataToDatabase(sportsData: TodaySportsData, healthData: HealthData): Promise<void> {
    try {
      const record = new HealthRecord();
      const date: string = new Date().toISOString().split('T')[0];
      const userId: number = HealthDataService.getCurrentUserId();
      record.initialize(date, userId);

      record.stepsCurrent = sportsData.steps.current;
      record.stepsGoal = sportsData.steps.goal;
      record.stepsDistance = sportsData.steps.distance;
      record.caloriesCurrent = sportsData.calories.current;
      record.caloriesGoal = sportsData.calories.goal;

      record.sleepDeep = healthData.sleep.deepSleep;
      record.sleepLight = 0;
      record.sleepTotal = healthData.sleep.deepSleep;
      record.stressValue = healthData.stress.value;
      record.heartRate = healthData.heart.heartRate;
      record.bpSystolic = healthData.bloodPressure.systolic;
      record.bpDiastolic = healthData.bloodPressure.diastolic;
      record.spo2 = healthData.bloodOxygen.spo2;
      record.temperature = healthData.temperature.value;

      await HealthDataService.saveSportsData(record);
      console.info('数据同步到数据库成功');
    } catch (error) {
      console.error(`数据同步到数据库失败: ${JSON.stringify(error)}`);
    }
  }

  // 新增接口 - 保存运动数据（用于数据编辑）
  static async saveSportsData(date: string, steps: number, calories: number, distance: number): Promise<void> {
    const userId: number = HealthDataService.getCurrentUserId();
    const record = new HealthRecord();
    record.initialize(date, userId);
    record.stepsCurrent = steps;
    record.caloriesCurrent = calories;
    record.stepsDistance = distance;

    await HealthDataService.saveSportsData(record);
  }

  // 新增接口 - 保存健康数据（用于数据编辑）
  static async saveHealthData(date: string, sleepDeep: number, sleepLight: number, stressValue: number,
    heartRate: number, bpSystolic: number, bpDiastolic: number, spo2: number, temperature: number): Promise<void> {
    const userId: number = HealthDataService.getCurrentUserId();
    const record = new HealthRecord();
    record.initialize(date, userId);
    record.sleepDeep = sleepDeep;
    record.sleepLight = sleepLight;
    record.sleepTotal = sleepDeep + sleepLight;
    record.stressValue = stressValue;
    record.heartRate = heartRate;
    record.bpSystolic = bpSystolic;
    record.bpDiastolic = bpDiastolic;
    record.spo2 = spo2;
    record.temperature = temperature;

    await HealthDataService.saveHealthData(record);
  }

  // 新增接口 - 根据日期获取健康数据
  static async getHealthDataByDate(date: string): Promise<HealthRecord | null> {
    return await HealthDataService.getHealthDataByDate(date);
  }

  // 新增接口 - 获取日期范围内的健康数据
  static async getHealthDataByDateRange(startDate: string, endDate: string): Promise<HealthRecord[]> {
    return await HealthDataService.getHealthDataByDateRange(startDate, endDate);
  }

  // 新增接口 - 删除健康数据
  static async deleteHealthData(date: string): Promise<void> {
    await HealthDataService.deleteHealthData(date);
  }

  // 新增接口 - 批量保存健康数据
  static async batchSaveHealthData(records: HealthRecord[]): Promise<void> {
    await HealthDataService.batchSaveHealthData(records);
  }

  // 新增接口 - 获取AI健康建议
  static async getAIAdvice(): Promise<AIAdviceResponse> {
    return await HealthDataService.getAIAdvice();
  }

  // 新增接口 - 设置当前登录用户ID
  static async setCurrentUserId(userId: number): Promise<void> {
    await HealthDataService.setCurrentUserIdValue(userId);
  }

  // 新增接口 - 获取当前登录用户ID
  static getCurrentUserId(): number {
    return HealthDataService.getCurrentUserId();
  }

  // 新增接口 - 更新当前登录用户ID（用于切换用户）
  static async updateCurrentUserId(userId: number): Promise<void> {
    await HealthDataService.updateCurrentUserId(userId);
  }

  // 新增接口 - 清空当前用户所有健康数据（用于测试）
  static async clearAllData(): Promise<void> {
    await HealthDataService.clearAllData();
  }


}