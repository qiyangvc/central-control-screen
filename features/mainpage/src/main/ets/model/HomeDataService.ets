import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from 'utils';

export interface EnergyData {
  power: number;      // 实时功率 (kW)
  todayUsage: number; // 今日用电 (kWh)
  carbon: number;     // 碳排 (kg)
}

export interface NetworkData {
  uploadSpeed: string;   // 上行速度
  downloadSpeed: string; // 下行速度
  quality: string;       // 网络质量
}

export interface WeatherData {
  tempC: number;
  condition: string;
  tip: string;
  icon: string;
  city: string;
}

export class HomeDataService {
  /**
   * 获取家庭能耗数据
   */
  static async getEnergyData(userId: number): Promise<EnergyData> {
    try {
      const store = AppDatabase.getStore();
      if (store) {
        const predicates = new relationalStore.RdbPredicates('house_metrics');
        predicates.equalTo('user_id', userId);
        predicates.orderByDesc('ts');
        predicates.limitAs(1); // SQL: SELECT * FROM house_metrics WHERE user_id = ? ORDER BY ts DESC LIMIT 1
        
        const resultSet: relationalStore.ResultSet = await store.query(predicates);
        if (resultSet.goToFirstRow()) {
          const energy = resultSet.getDouble(resultSet.getColumnIndex('energy_kwh'));
          const co2 = resultSet.getDouble(resultSet.getColumnIndex('co2_ppm'));
          resultSet.close();
          
          // 实时功率不再随机生成，而是基于今日用电量计算一个伪随机但固定的值
          // 算法：(energy * 100) 的小数部分 * 2 + 0.5
          // 这样只要 energy 不变，power 就不变；energy 变了，power 也会变
          const pseudoRandom = (energy * 13.7) % 1; 
          const powerVal = pseudoRandom * 2 + 0.5;

          return {
            power: parseFloat(powerVal.toFixed(2)), 
            todayUsage: parseFloat(energy.toFixed(1)),
            carbon: parseFloat((co2 / 1000).toFixed(2))
          };
        }
        resultSet.close();
      }
    } catch (e) {
      console.warn('HomeDataService: 读取数据库失败，使用随机数据', e);
    }

    // 针对不同用户生成不同的默认基准值
    // const baseUsage = (userId % 3) * 2 + 2; // 2, 4, 6
    return {
      power: 0, // parseFloat((Math.random() * 2 + 0.5).toFixed(2)), // 0.5 - 2.5 kW
      todayUsage: 0, // parseFloat((Math.random() * 5 + baseUsage).toFixed(1)), 
      carbon: 0 // parseFloat((Math.random() * 1 + 0.2).toFixed(2))   // 0.2 - 1.2 kg
    };
  }

  /**
   * 获取家庭网络数据
   */
  static async getNetworkData(userId: number): Promise<NetworkData> {
    try {
      const store = AppDatabase.getStore();
      if (store) {
        const predicates = new relationalStore.RdbPredicates('house_metrics');
        predicates.equalTo('user_id', userId);
        predicates.orderByDesc('ts');
        predicates.limitAs(1);
        
        const resultSet = await store.query(predicates);
        if (resultSet.goToFirstRow()) {
          const down = resultSet.getDouble(resultSet.getColumnIndex('net_down_mbps'));
          const up = resultSet.getDouble(resultSet.getColumnIndex('net_up_mbps'));
          resultSet.close();
          
          return {
            downloadSpeed: `${down.toFixed(0)} Mbps`,
            uploadSpeed: `${up.toFixed(0)} Mbps`,
            quality: down > 300 ? '优' : '良'
          };
        }
        resultSet.close();
      }
    } catch (e) {
      console.warn('HomeDataService: 读取网络数据失败', e);
    }

    // const baseSpeed = (userId % 2 === 0) ? 300 : 100;
    // const down = Math.floor(Math.random() * 200 + baseSpeed); 
    // const up = Math.floor(down / 10);
    
    return {
      downloadSpeed: `0 Mbps`,
      uploadSpeed: `0 Mbps`,
      quality: '未知'
    };
  }

  /**
   * 模拟插入一条新数据 (写库操作)
   */
  static async simulateData(userId: number): Promise<void> {
    try {
      const store = AppDatabase.getStore();
      if (!store) return;
      
      // 读取上一条数据作为基准
      const lastEnergy = await HomeDataService.getEnergyData(userId);
      const lastNet = await HomeDataService.getNetworkData(userId); // Note: this calls getStore again, fine.
      
      // === 差异化模拟逻辑 ===
      // 根据 userId 设定不同的模拟参数，确保数据特征不同
      let energyGrowth = 0.5;
      let netFluctuation = 50;
      let co2Growth = 50;

      if (userId === 1) {
         // 用户1: 模拟高能耗家庭，网络波动大
         energyGrowth = Math.random() * 1.5 + 0.5; // 0.5 - 2.0 kWh 增长
         netFluctuation = 100; // 波动幅度 +/- 50
         co2Growth = 100;
      } else if (userId === 2) {
         // 用户2: 模拟节能家庭，网络稳定
         energyGrowth = Math.random() * 0.3 + 0.1; // 0.1 - 0.4 kWh 增长
         netFluctuation = 20; // 波动幅度 +/- 10
         co2Growth = 20;
      } else {
         // 其他用户: 随机
         energyGrowth = Math.random() * 0.8;
         netFluctuation = 60;
         co2Growth = 60;
      }

      // 随机波动
      const newEnergy = lastEnergy.todayUsage + energyGrowth;
      const newCo2 = (lastEnergy.carbon * 1000) + (Math.random() * co2Growth);
      
      let newDown = parseFloat(lastNet.downloadSpeed) + (Math.random() * netFluctuation - (netFluctuation / 2));
      if (newDown < 100) newDown = 100;
      const newUp = newDown / 10;

      const valueBucket: relationalStore.ValuesBucket = {
        user_id: userId,
        ts: new Date().getTime().toString(), // Use timestamp string
        energy_kwh: newEnergy,
        net_up_mbps: newUp,
        net_down_mbps: newDown,
        light_lux: 500, // default
        co2_ppm: newCo2,
        updated_at: new Date().toISOString()
      };

      // 插入一条新的历史记录，保留了历史轨迹
      await store.insert('house_metrics', valueBucket);
      console.info(`HomeDataService: 用户${userId} 模拟数据插入成功`);

    } catch (error) {
      console.error('HomeDataService: 模拟数据插入失败', JSON.stringify(error));
    }
  }

  static getWeatherData(): WeatherData {
    const samples: WeatherData[] = [
      { tempC: 26, condition: '多云转晴', tip: '今日紫外线较强，出门请注意防晒。', icon: 'sun', city: '深圳' },
      { tempC: 18, condition: '小雨', tip: '出门记得带伞，注意防滑。', icon: 'rain', city: '深圳' },
      { tempC: 32, condition: '晴', tip: '天气炎热，补水降温。', icon: 'sun', city: '深圳' },
      { tempC: 5, condition: '阴', tip: '气温较低，注意保暖。', icon: 'cloud', city: '深圳' }
    ];
    const idx = Math.floor(Math.random() * samples.length);
    return samples[idx];
  }
}
