import router from '@ohos.router';
import { HealthSportsViewModel } from '../viewmodel/HealthSportsViewModel';
// 引入编辑页文件，确保命名路由 'HealthDataEditPage' 被注册
import './HealthDataEditPage';

interface UISportsData {
  stepsStr: string;
  stepsPercent: number;
  kcalStr: string;
  kcalPercent: number;
  heartRateStr: string;
  sleepStr: string;
  distanceStr: string;
  bloodPressureStr: string;
  spo2Str: string;
  tempStr: string;
  stressStr: string;
  sleepDateStr: string;
  stressDateStr: string;
  heartDateStr: string;
  bpDateStr: string;
  spo2DateStr: string;
  tempDateStr: string;
  stepsProgressStr: string;
  kcalProgressStr: string;
  deepSleepStr: string;
  lightSleepStr: string;
}

@Entry({ routeName: 'HealthSportsPage' })
@Component
export struct HealthSportsPage {
  // 监听全局数据更新事件 (由 HealthDataEditPage 触发)
  @StorageProp('HealthDataLastUpdate') @Watch('onHealthDataUpdate') lastUpdate: number = 0;
  
  // ⚡️ 接收来自个人信息页面的目标设置
  @StorageProp('targetSteps') @Watch('loadData') targetSteps: number = 10000;
  @StorageProp('targetCalories') @Watch('loadData') targetCalories: number = 500;

  @State ui: UISportsData = {
    stepsStr: '--',
    stepsPercent: 0,
    kcalStr: '--',
    kcalPercent: 0,
    heartRateStr: '--',
    sleepStr: '--',
    distanceStr: '--',
    bloodPressureStr: '--/--',
    spo2Str: '--%',
    tempStr: '--°C',
    stressStr: '--',
    sleepDateStr: '--/--',
    stressDateStr: '--/--',
    heartDateStr: '--/--',
    bpDateStr: '--/--',
    spo2DateStr: '--/--',
    tempDateStr: '--/--',
    stepsProgressStr: '0/10000',
    kcalProgressStr: '0/500',
    deepSleepStr: '-- h',
    lightSleepStr: '-- h'
  };

  // 当监听到数据更新时，自动重新加载数据
  onHealthDataUpdate() {
    console.info('HealthSportsPage: 监听到数据更新通知，正在刷新...');
    setTimeout(() => {
      this.loadData();
    }, 100);
  }

  async aboutToAppear() {
    // 初始化数据库服务
    await HealthSportsViewModel.init(getContext(this));
    await this.loadData();
  }

  async onPageShow() {
    await this.loadData();
  }

  async loadData() {
    console.info('=== HealthSportsPage: 开始加载数据 ===');
    const viewModel = new HealthSportsViewModel();
    try {
      console.info('调用getTodaySports...');
      const sportsData = await viewModel.getTodaySports();
      console.info('运动数据:', JSON.stringify(sportsData));

      const currentSteps = sportsData.steps?.current || 0;
      // ⚡️ 使用全局设置的目标步数
      const goalSteps = this.targetSteps || sportsData.steps?.goal || 10000;

      this.ui.stepsStr = currentSteps.toString();
      this.ui.stepsPercent = (currentSteps / goalSteps) * 100;
      this.ui.stepsProgressStr = `${currentSteps}/${goalSteps}`;
      this.ui.distanceStr = (sportsData.steps?.distance || 0).toFixed(1) + ' km';

      const currentKcal = sportsData.calories?.current || 0;
      // ⚡️ 使用全局设置的目标热量
      const goalKcal = this.targetCalories || sportsData.calories?.goal || 500;

      this.ui.kcalStr = currentKcal.toString();
      this.ui.kcalPercent = (currentKcal / goalKcal) * 100;
      this.ui.kcalProgressStr = `${currentKcal}/${goalKcal}`;

      console.info('调用getHealthData...');
      const healthData = await viewModel.getHealthData();
      console.info('健康数据:', JSON.stringify(healthData));

      console.info('heart.heartRate:', healthData.heart?.heartRate);
      console.info('sleep.totalSleep:', healthData.sleep?.totalSleep);
      console.info('stress.value:', healthData.stress?.value);

      this.ui.heartRateStr = (healthData.heart.heartRate || 0) + ' bpm';

      const sleepTotal = healthData.sleep.totalSleep || 0;
      const sleepDeep = healthData.sleep.deepSleep || 0;
      const sleepLight = healthData.sleep.lightSleep || 0;
      const sleepValue = sleepTotal > 0 ? sleepTotal : sleepDeep;
      this.ui.sleepStr = sleepValue.toFixed(1) + ' h';
      this.ui.deepSleepStr = sleepDeep.toFixed(1) + ' h';
      this.ui.lightSleepStr = sleepLight.toFixed(1) + ' h';

      this.ui.bloodPressureStr = `${healthData.bloodPressure.systolic}/${healthData.bloodPressure.diastolic} mmHg`;
      this.ui.spo2Str = (healthData.bloodOxygen.spo2 || 0) + ' %';
      this.ui.tempStr = (healthData.temperature.value || 0).toFixed(1) + ' °C';
      this.ui.stressStr = (healthData.stress.value || 0).toString();

      this.ui.sleepDateStr = healthData.sleep.date || '--/--';
      this.ui.stressDateStr = healthData.stress.date || '--/--';
      this.ui.heartDateStr = healthData.heart.date || '--/--';
      this.ui.bpDateStr = healthData.bloodPressure.date || '--/--';
      this.ui.spo2DateStr = healthData.bloodOxygen.date || '--/--';
      this.ui.tempDateStr = healthData.temperature.date || '--/--';

      console.info('UI更新完成');
      console.info('heartRateStr:', this.ui.heartRateStr);
      console.info('sleepStr:', this.ui.sleepStr);
      console.info('stressStr:', this.ui.stressStr);
    } catch (error) {
      console.error('获取运动健康数据失败:', error);
    }
  }

  build() {
    Stack() {
      // 1. 背景层
      Image($r('app.media.bg_wellness'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      // 2. 遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0, 0.45)')

      // 3. 内容层
      Column() {
        // =========================================================
        // (1) 顶部导航栏 (包含右上角数据录入入口)
        // =========================================================
        Row() {
          Image($r('app.media.icon_back'))
            .width(24).height(24)
            .fillColor(Color.White)
            .onClick(() => router.back())

          Text('运动健康')
            .fontSize(20)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 16 })

          // 【关键点】使用 Blank() 占据中间空间，把后面的按钮推到最右边
          Blank()

          // 【保留】右上角的数据录入入口
          Row() {
            // 可选：加个小图标
            // Image($r('app.media.icon_edit')).width(16).height(16).fillColor(Color.White).margin({right:4})
            Text('数据录入')
              .fontColor(Color.White)
              .fontSize(14)
          }
          .padding({ top: 6, bottom: 6, left: 12, right: 12 })
          .backgroundColor('rgba(255,255,255,0.2)') // 半透明背景
          .borderRadius(20)
          .onClick(() => {
            try {
              router.pushNamedRoute({
                name: 'HealthDataEditPage'
              });
            } catch (e) {
              console.error('跳转失败:', JSON.stringify(e));
            }
          })
        }
        .width('100%')
        .padding({ top: 40, left: 20, right: 20, bottom: 10 }) // 确保 right padding 足够
        .alignItems(VerticalAlign.Center)

        // =========================================================
        // (2) 核心仪表盘 (中间区域 - 纯展示)
        // =========================================================
        Row() {
          // --- 左侧圆环：步数 ---
          Stack({ alignContent: Alignment.Center }) {
            Progress({ value: 100, total: 100, type: ProgressType.Ring })
              .width(150).color('rgba(255,255,255,0.1)').style({ strokeWidth: 12 })
            Progress({ value: this.ui.stepsPercent, total: 100, type: ProgressType.Ring })
              .width(150).color('#0A84FF').style({ strokeWidth: 12 })
            Column() {
              Text('步数').fontSize(12).fontColor('rgba(255,255,255,0.6)')
              Text(this.ui.stepsPercent.toFixed(0) + '%').fontSize(28).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text(this.ui.stepsProgressStr).fontSize(10).fontColor('rgba(255,255,255,0.4)').margin({ top: 2 })
            }
          }.layoutWeight(1)

          // --- 右侧圆环：热量 ---
          Stack({ alignContent: Alignment.Center }) {
            Progress({ value: 100, total: 100, type: ProgressType.Ring })
              .width(150).color('rgba(255,255,255,0.1)').style({ strokeWidth: 12 })
            Progress({ value: this.ui.kcalPercent, total: 100, type: ProgressType.Ring })
              .width(150).color('#FF9F0A').style({ strokeWidth: 12 })
            Column() {
              Text('热量').fontSize(12).fontColor('rgba(255,255,255,0.6)')
              Text(this.ui.kcalPercent.toFixed(0) + '%').fontSize(28).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text(this.ui.kcalProgressStr).fontSize(10).fontColor('rgba(255,255,255,0.4)').margin({ top: 2 })
            }
          }.layoutWeight(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: 10, right: 10 })
        .margin({ top: 30, bottom: 30 })

        // =========================================================
        // (3) 数据卡片网格 (底部区域 - 纯展示)
        // =========================================================
        Grid() {
          ForEach([
            { title: '睡眠', value: this.ui.sleepStr, date: this.ui.sleepDateStr, icon: $r('app.media.icon_sleep_quality'), color: '#30D158', key: 'sleep' },
            { title: '压力', value: this.ui.stressStr, date: this.ui.stressDateStr, icon: $r('app.media.icon_pressure'), color: '#00D1FF', key: 'stress' },
            { title: '心率', value: this.ui.heartRateStr, date: this.ui.heartDateStr, icon: $r('app.media.icon_heart_rate'), color: '#FF375F', key: 'heart' },
            { title: '血压', value: this.ui.bloodPressureStr, date: this.ui.bpDateStr, icon: $r('app.media.icon_bloodpressure'), color: '#5E5CE6', key: 'bp' },
            { title: '血氧', value: this.ui.spo2Str, date: this.ui.spo2DateStr, icon: $r('app.media.icon_blood_oxygen'), color: '#64D2FF', key: 'spo2' },
            { title: '体温', value: this.ui.tempStr, date: this.ui.tempDateStr, icon: $r('app.media.icon_body_temperature'), color: '#FFD60A', key: 'temp' },
            { title: '深睡眠', value: this.ui.deepSleepStr, date: this.ui.sleepDateStr, icon: $r('app.media.icon_sleep_quality'), color: '#5856D6', key: 'deep_sleep' },
            { title: '浅睡眠', value: this.ui.lightSleepStr, date: this.ui.sleepDateStr, icon: $r('app.media.icon_sleep_quality'), color: '#AF52DE', key: 'light_sleep' }
          ], (item: Record<string, Object>) => {
            GridItem() {
              this.DataCard(item.title as string, item.value as string, item.date as string, item.icon as Resource, item.color as string)
            }
          })
        }
        .columnsTemplate('1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .padding({ left: 16, right: 16, bottom: 20 })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder DataCard(title: string, value: string, date: string, icon: Resource, color: string) {
    Column() {
      Row() {
        Image(icon).width(20).height(20).fillColor(Color.White)
        Text(title).fontSize(14).fontColor('rgba(255,255,255,0.8)').margin({ left: 8 })
      }.width('100%').alignItems(VerticalAlign.Center)

      Text(value).fontSize(18).fontWeight(FontWeight.Medium).fontColor(Color.White).margin({ top: 10 })
      Text(date).fontSize(12).fontColor('rgba(255,255,255,0.5)').margin({ top: 4 })
    }
    .width('100%')
    .height(110)
    .backgroundColor('rgba(255, 255, 255, 0.1)')
    .backdropBlur(20)
    .borderRadius(16)
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: { left: 4 }, color: color })
  }
}