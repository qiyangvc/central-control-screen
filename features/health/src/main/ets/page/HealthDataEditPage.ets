import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
// 引用已写好的后端服务
import { HealthDataService, HealthRecord } from '../database/HealthDataService';

@Entry({ routeName: 'HealthDataEditPage' })
@Component
export struct HealthDataEditPage {
  // === 状态变量 ===
  @State selectedDate: Date = new Date(); // 当前选中的日期
  @State dateStr: string = ''; // 日期字符串 (YYYY-MM-DD)
  @State isDataExist: boolean = false; // 【关键】标记当前日期是否有数据 (用于控制删除按钮显示)

  // === 表单数据绑定 ===
  @State steps: string = '';
  @State calories: string = '';
  @State distance: string = '';
  @State deepSleep: string = '';
  @State lightSleep: string = '';
  @State heartRate: string = '';
  @State stress: string = '';
  @State bpSystolic: string = '';
  @State bpDiastolic: string = '';
  @State spo2: string = '';
  @State temperature: string = '';
  @State refreshKey: number = 0; // 用于强制刷新UI

  // === 生命周期 ===
  async aboutToAppear() {
    this.dateStr = HealthDataService.formatDate(this.selectedDate);
    // 初始化数据库 (确保服务可用)
    await HealthDataService.init(getContext(this));
    // 进入页面时默认【查找】今天的数据
    this.queryData(this.dateStr);
  }

  // === 功能 1: 查找 (Query) ===
  // 根据日期从后端加载数据
  async queryData(date: string) {
    try {
      // 调用后端查找接口
      const record = await HealthDataService.getHealthDataByDate(date);

      if (record) {
        this.isDataExist = true; // 标记为已存在 (修改模式)

        // 打印查询到的数据用于调试
        console.info('HealthDataEditPage: 查询到的原始数据', JSON.stringify({
          stepsCurrent: record.stepsCurrent,
          caloriesCurrent: record.caloriesCurrent,
          stepsDistance: record.stepsDistance,
          sleepDeep: record.sleepDeep,
          sleepLight: record.sleepLight,
          sleepTotal: record.sleepTotal,
          heartRate: record.heartRate,
          stressValue: record.stressValue,
          bpSystolic: record.bpSystolic,
          bpDiastolic: record.bpDiastolic,
          spo2: record.spo2,
          temperature: record.temperature
        }));

        // 先清空所有字段，再设置新值，触发UI刷新
        this.steps = '';
        this.calories = '';
        this.distance = '';
        this.deepSleep = '';
        this.lightSleep = '';
        this.heartRate = '';
        this.stress = '';
        this.bpSystolic = '';
        this.bpDiastolic = '';
        this.spo2 = '';
        this.temperature = '';

        // 回显数据到表单
        this.steps = record.stepsCurrent > 0 ? record.stepsCurrent.toString() : '';
        this.calories = record.caloriesCurrent > 0 ? record.caloriesCurrent.toString() : '';
        this.distance = record.stepsDistance > 0 ? record.stepsDistance.toString() : '';

        this.deepSleep = record.sleepDeep > 0 ? record.sleepDeep.toString() : '';
        this.lightSleep = record.sleepLight > 0 ? record.sleepLight.toString() : '';

        this.heartRate = record.heartRate > 0 ? record.heartRate.toString() : '';
        this.stress = record.stressValue > 0 ? record.stressValue.toString() : '';
        this.bpSystolic = record.bpSystolic > 0 ? record.bpSystolic.toString() : '';
        this.bpDiastolic = record.bpDiastolic > 0 ? record.bpDiastolic.toString() : '';
        this.spo2 = record.spo2 > 0 ? record.spo2.toString() : '';
        this.temperature = record.temperature > 0 ? record.temperature.toString() : '';

        // 打印设置后的表单值用于调试
        console.info('HealthDataEditPage: 设置后的表单值', JSON.stringify({
          steps: this.steps,
          calories: this.calories,
          distance: this.distance,
          deepSleep: this.deepSleep,
          lightSleep: this.lightSleep,
          heartRate: this.heartRate,
          stress: this.stress,
          bpSystolic: this.bpSystolic,
          bpDiastolic: this.bpDiastolic,
          spo2: this.spo2,
          temperature: this.temperature
        }));

        // 强制刷新UI
        this.refreshKey++;

        promptAction.showToast({ message: `查询成功: 已加载 ${date} 数据` });
      } else {
        this.isDataExist = false; // 标记为不存在 (新增模式)
        this.clearForm(); // 清空表单
        // promptAction.showToast({ message: `${date} 暂无数据，请录入` });
      }
    } catch (e) {
      console.error('Query failed', e);
      promptAction.showToast({ message: '查询失败' });
    }
  }

  // === 功能 2 & 3: 增加 (Add) & 修改 (Modify) ===
  // 提交数据到后端 (后端 saveHealthData 自动处理 新增或更新)
  async saveOrUpdateData() {
    try {
      const userId = HealthDataService.getCurrentUserId();

      // 1. 先尝试获取当天的现有数据，避免覆盖未修改的字段
      let record = await HealthDataService.getHealthDataByDate(this.dateStr);
      
      if (!record) {
        // 如果没有，则创建新记录
        record = new HealthRecord();
        record.initialize(this.dateStr, userId);
      }

      // 2. 填充数据 (仅当输入框有值时才更新，否则保留原值)
      // 注意：如果用户清空了输入框，这里可能需要特殊处理，目前逻辑是保留原值
      if (this.steps) record.stepsCurrent = parseInt(this.steps);
      if (this.calories) record.caloriesCurrent = parseInt(this.calories);
      if (this.distance) record.stepsDistance = parseFloat(this.distance);

      if (this.deepSleep) record.sleepDeep = parseFloat(this.deepSleep);
      if (this.lightSleep) record.sleepLight = parseFloat(this.lightSleep);
      
      // 重新计算总睡眠 (如果修改了深睡或浅睡)
      if (this.deepSleep || this.lightSleep) {
         record.sleepTotal = record.sleepDeep + record.sleepLight;
      }

      if (this.heartRate) record.heartRate = parseInt(this.heartRate);
      if (this.stress) record.stressValue = parseInt(this.stress);
      if (this.bpSystolic) record.bpSystolic = parseInt(this.bpSystolic);
      if (this.bpDiastolic) record.bpDiastolic = parseInt(this.bpDiastolic);
      if (this.spo2) record.spo2 = parseInt(this.spo2);
      if (this.temperature) record.temperature = parseFloat(this.temperature);

      // 调用后端保存接口
      await HealthDataService.saveHealthData(record);

      // 核心修复：保存成功后，立即通知全局“健康数据已更新”
      // 这样 WellnessPage (居家康养) 和 HealthSportsPage (运动健康) 都能监听到并自动刷新
      AppStorage.setOrCreate('HealthDataLastUpdate', Date.now());

      // === 终极修复：直接更新 AppStorage 中的气泡显示数据 ===
      // 这样 WellnessPage 即使不读数据库，也能立即显示最新值
      // 注意：这里使用 record 中的值，因为 record 已经是合并后的完整数据
      AppStorage.setOrCreate('Health_Bubble_Temp', (record.temperature || 0).toFixed(1));
      AppStorage.setOrCreate('Health_Bubble_Heart', (record.heartRate || 0).toString());
      AppStorage.setOrCreate('Health_Bubble_Spo2', (record.spo2 || 0).toString());
      AppStorage.setOrCreate('Health_Bubble_BP', `${record.bpSystolic || 0}/${record.bpDiastolic || 0}`);
      AppStorage.setOrCreate('Health_Bubble_Stress', (record.stressValue || 0).toString());

      promptAction.showToast({ message: this.isDataExist ? '修改成功！' : '新增成功！' });

      // 保存后刷新状态
      this.isDataExist = true;

      // 延迟返回上一页
      setTimeout(() => {
        router.back();
      }, 500);

    } catch (error) {
      console.error('Save failed', error);
      promptAction.showToast({ message: '保存失败: ' + JSON.stringify(error) });
    }
  }

  // === 功能 4: 删除 (Delete) ===
  // 删除当前日期的数据
  async deleteCurrentData() {
    AlertDialog.show({
      title: '确认删除',
      message: `确定要删除 ${this.dateStr} 的所有健康数据吗？此操作不可恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: async () => {
          try {
            // 调用后端删除接口
            await HealthDataService.deleteHealthData(this.dateStr);

            promptAction.showToast({ message: '删除成功' });
            this.isDataExist = false;
            this.clearForm(); // 清空界面

          } catch (e) {
            console.error('Delete failed', e);
            promptAction.showToast({ message: '删除失败' });
          }
        }
      }
    });
  }

  // 辅助方法：清空表单
  clearForm() {
    this.steps = ''; this.calories = ''; this.distance = '';
    this.deepSleep = ''; this.lightSleep = '';
    this.heartRate = ''; this.stress = '';
    this.bpSystolic = ''; this.bpDiastolic = '';
    this.spo2 = ''; this.temperature = '';
  }

  // 辅助方法：显示日期选择器
  showDatePicker() {
    DatePickerDialog.show({
      start: new Date("2020-01-01"),
      end: new Date(), // 限制只能选择今天及以前的日期
      selected: this.selectedDate,
      onAccept: (value: DatePickerResult) => {
        const newDate = new Date(value.year!, value.month!, value.day!);
        this.selectedDate = newDate;
        this.dateStr = HealthDataService.formatDate(newDate);
        // 选中日期后，立即触发【查找】
        this.queryData(this.dateStr);
      }
    })
  }

  // === UI 构建 ===
  build() {
    Column() {
      // 1. 顶部导航栏
      Row() {
        Image($r('app.media.icon_back'))
          .width(24).height(24)
          .fillColor($r('app.color.text_white'))
          .onClick(() => router.back())
        Text('健康数据管理') // 修改标题以体现管理功能
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_white'))
          .margin({ left: 16 })
      }
      .width('100%')
      .padding({ top: 40, left: 20, bottom: 20 })
      .backgroundColor($r('app.color.bg_card'))
      .shadow({ radius: 2, color: 'rgba(0,0,0,0.05)', offsetY: 2 })

      // 2. 主内容滚动区
      Scroll() {
        Column({ space: 16 }) {

          // --- 查找区域 (Query) ---
          this.FormItemTitle('查找 / 日期选择')
          Row() {
            Text('当前日期: ' + this.dateStr)
              .fontSize(16)
              .fontColor($r('app.color.text_white'))
              .layoutWeight(1)

            // 查找/切换日期按钮
            Button('切换日期 / 查找')
              .fontSize(14)
              .height(32)
              .backgroundColor('#0A84FF')
              .onClick(() => this.showDatePicker())
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(8)

          // --- 数据录入区域 (Add/Modify) ---
          this.FormItemTitle('运动数据')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            Column() {
              Text('步数').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '8000', text: this.steps })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.steps = v)
            }
            .width('48%')
            .margin({ bottom: 12 })

            Column() {
              Text('热量(kcal)').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '500', text: this.calories })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.calories = v)
            }
            .width('48%')
            .margin({ bottom: 12 })

            Column() {
              Text('距离(km)').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '5.2', text: this.distance })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.distance = v)
            }
            .width('48%')
            .margin({ bottom: 12 })
          }

          this.FormItemTitle('睡眠数据 (小时)')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            Column() {
              Text('深睡').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '2.5', text: this.deepSleep })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.deepSleep = v)
            }
            .width('48%')
            .margin({ bottom: 12 })

            Column() {
              Text('浅睡').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '5.0', text: this.lightSleep })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.lightSleep = v)
            }
            .width('48%')
            .margin({ bottom: 12 })
          }

          this.FormItemTitle('身体指标')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            Column() {
              Text('心率(bpm)').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '75', text: this.heartRate })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.heartRate = v)
            }
            .width('48%')
            .margin({ bottom: 12 })

            Column() {
              Text('血氧(%)').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '98', text: this.spo2 })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.spo2 = v)
            }
            .width('48%')
            .margin({ bottom: 12 })

            Column() {
              Text('体温(°C)').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '36.5', text: this.temperature })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.temperature = v)
            }
            .width('48%')
            .margin({ bottom: 12 })

            Column() {
              Text('压力值(0-99)').fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
              TextInput({ placeholder: '40', text: this.stress })
                .type(InputType.NUMBER_DECIMAL)
                .width('100%')
                .height(45)
                .backgroundColor('#F5F7FA')
                .borderRadius(8)
                .onChange((v) => this.stress = v)
            }
            .width('48%')
            .margin({ bottom: 12 })
          }

          this.FormItemTitle('血压 (mmHg)')
          Row({ space: 10 }) {
            TextInput({ placeholder: '收缩压(高压)', text: this.bpSystolic })
              .type(InputType.Number)
              .layoutWeight(1)
              .height(45)
              .backgroundColor($r('app.color.input_bg'))
              .fontColor($r('app.color.text_white'))
              .borderRadius(8)
              .onChange((val) => this.bpSystolic = val)
            Text('/').fontSize(20).fontColor(Color.Gray)
            TextInput({ placeholder: '舒张压(低压)', text: this.bpDiastolic })
              .type(InputType.Number)
              .layoutWeight(1)
              .height(45)
              .backgroundColor($r('app.color.input_bg'))
              .fontColor($r('app.color.text_white'))
              .borderRadius(8)
              .onChange((val) => this.bpDiastolic = val)
          }.width('100%')

          // --- 操作按钮区域 ---
          Column({ space: 12 }) {
            // 按钮 1: 保存 (对应 Add 和 Modify)
            Button(this.isDataExist ? '修改保存' : '确认新增', { type: ButtonType.Capsule })
              .width('100%')
              .height(50)
              .fontSize(18)
              .backgroundColor('#0A84FF')
              .onClick(() => this.saveOrUpdateData())

            // 按钮 2: 删除 (对应 Delete) - 仅当有数据时显示
            if (this.isDataExist) {
              Button('删除此条数据', { type: ButtonType.Capsule })
                .width('100%')
                .height(50)
                .fontSize(18)
                .backgroundColor('#FF3B30') // 红色警告色
                .margin({ top: 10 })
                .onClick(() => this.deleteCurrentData())
            }
          }
          .margin({ top: 30, bottom: 50 })

        }
        .padding(20)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  // --- UI 组件封装 ---
  @Builder FormItemTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .width('100%')
      .margin({ top: 12, bottom: 8 })
      .fontColor($r('app.color.text_white'))
  }

  @Builder InputBox(label: string, placeholder: string, value: string, onChange: (val: string) => void) {
    Column() {
      Text(label).fontSize(12).fontColor(Color.Gray).margin({ bottom: 4 }).width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .type(InputType.NUMBER_DECIMAL)
        .width('100%')
        .height(45)
        .backgroundColor($r('app.color.input_bg'))
        .fontColor($r('app.color.text_white'))
        .borderRadius(8)
        .onChange(onChange)
        .key(label + value) // 添加key以强制刷新
    }
    .width('48%')
    .margin({ bottom: 12 })
  }
}