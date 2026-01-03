import { NavigationModel } from '../model/NavigationModel';
import router from '@ohos.router';
import  {MenuItem} from '../model/btn'// 定义菜单接口
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { HealthData } from '../model/SportsDataModel';
import { HealthSportsViewModel } from '../viewmodel/HealthSportsViewModel';
import { HealthDataService } from '../database/HealthDataService';
import { UserRepo, UserProfile, UserInfo } from 'auth';

@Entry({ routeName: 'HealthWellnessPage' })
@Component
export struct WellnessPage {
  private context = getContext(this) as common.UIAbilityContext;
  @State isDarkMode: boolean = false;
  @State healthData: HealthData = new HealthData();
  @State currentBreakpoint: string = 'xs'; // 默认设为 xs，防止初始闪烁
  
  // 监听全局数据更新事件 (由 HealthDataEditPage 触发)
  @StorageProp('HealthDataLastUpdate') @Watch('onHealthDataUpdate') lastUpdate: number = 0;

  private viewModel: HealthSportsViewModel = new HealthSportsViewModel();
  
  // 用户信息状态
  @State userName: string = '请登录';
  @State userPhone: string = '';
  @State userAge: number = 0;
  @State userGender: string = '未知';
  @State userHeight: number = 0;
  @State userWeight: number = 0;
  @State userBMI: number = 0;

  // === 扁平化状态变量 (使用 @StorageLink 实现跨页面双向同步) ===
  @StorageLink('Health_Bubble_Temp') tempVal: string = '--';
  @StorageLink('Health_Bubble_Heart') heartVal: string = '--';
  @StorageLink('Health_Bubble_Spo2') spo2Val: string = '--';
  @StorageLink('Health_Bubble_BP') bpVal: string = '--/--';
  @StorageLink('Health_Bubble_Stress') stressVal: string = '--';

  // 强制刷新 UI 的标记
  @State uiRefresher: number = 0;

  // 当监听到数据更新时，自动重新加载数据
  onHealthDataUpdate() {
    console.info('WellnessPage: 监听到数据更新通知，无需操作，AppStorage已自动同步');
    // 移除 loadHealthData 调用，完全信任 AppStorage 的直接更新
  }

  aboutToAppear() {
    // 同步系统当前的深浅模式状态
    let colorMode = this.context.config.colorMode;
    this.isDarkMode = (colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.loadUserProfile();
  }

  onPageShow() {
    console.info('WellnessPage: onPageShow triggered');
    
    // 如果最近2秒内有过数据更新，则跳过数据库加载，防止旧数据覆盖新数据
    const now = Date.now();
    if (now - this.lastUpdate < 2000) {
      console.info('WellnessPage: 检测到最近有数据更新，跳过数据库读取，使用 AppStorage 缓存');
      this.loadUserProfile();
      return;
    }

    this.loadHealthData();
    this.loadUserProfile();
  }

  async loadUserProfile() {
    const currentUser = AppStorage.get<UserInfo>('currentUser');
    if (currentUser) {
      this.userName = currentUser.name;
      try {
        // 获取完整画像以显示手机号
        const profile = await UserRepo.getUserProfile(currentUser.id);
        if (profile) {
          this.userName = profile.name || currentUser.name;
          this.userPhone = profile.phone || '';
          this.userAge = profile.age || 0;
          this.userGender = profile.gender || '未知';
          this.userHeight = profile.height || 0;
          this.userWeight = profile.weight || 0;
          
          // 计算BMI：体重(kg) / (身高(m) * 身高(m))
          if (this.userHeight > 0 && this.userWeight > 0) {
            const heightInMeters = this.userHeight / 100;
            this.userBMI = parseFloat((this.userWeight / (heightInMeters * heightInMeters)).toFixed(1));
          } else {
            this.userBMI = 0;
          }
        }
      } catch (e) {
        console.error('加载用户画像失败:', JSON.stringify(e as object));
      }
    }
  }

  async loadHealthData() {
    try {
      // 1. 确保数据库已初始化 (双重保险)
      await HealthDataService.init(this.context);
      
      // 2. 获取数据
      let data = await this.viewModel.getHealthData();
      
      // 3. 检查数据是否全为0 (如果是，说明可能是新用户，尝试自动生成一次数据)
      if (data.heart.heartRate === 0 && data.bloodOxygen.spo2 === 0) {
        console.info('WellnessPage: 检测到健康数据为空，尝试自动生成初始数据...');
        await HealthDataService.simulateData();
        // 重新获取
        data = await this.viewModel.getHealthData();
      }
      
      this.healthData = data;
      
      // 更新扁平化状态 (同时更新 AppStorage，确保下次进入时有缓存)
      this.tempVal = (data.temperature.value || 0).toFixed(1);
      this.heartVal = (data.heart.heartRate || 0).toString();
      this.spo2Val = (data.bloodOxygen.spo2 || 0).toString();
      this.bpVal = `${data.bloodPressure.systolic || 0}/${data.bloodPressure.diastolic || 0}`;
      this.stressVal = (data.stress.value || 0).toString();

      this.uiRefresher++; // 强制触发 UI 更新
      console.info('WellnessPage: 数据加载完成', JSON.stringify(this.healthData));

    } catch (error) {
      console.error(`加载健康数据失败: ${JSON.stringify(error as object)}`);
      // 如果出错，这里可以给 healthData 赋一个默认的模拟值，或者弹窗提示
    }
  }

  // 菜单配置：映射你上传的图片 (注意：文件名必须对应你media目录下的实际文件名，且必须小写)
  private menuList: MenuItem[] = [
    { title: $r('app.string.menu_record'), iconImg: $r('app.media.books'), key: 'card_record' }, // 健康档案 -> books
    { title: $r('app.string.menu_vital'), iconImg: $r('app.media.heart_waves_fill'), key: 'card_vital' }, // 体征 -> heart
    { title: $r('app.string.menu_sport'), iconImg: $r('app.media.running'), key: 'btn_sport_health' }, // 运动 -> running
    { title: $r('app.string.menu_edu'), iconImg: $r('app.media.preach'), key: 'card_edu' }, // 宣教 -> preach
    { title: $r('app.string.menu_consult'), iconImg: $r('app.media.icon_consultation'), key: 'card_consult' }, // 问诊 -> consultation (记得改小写)
    { title: $r('app.string.menu_nurse'), iconImg: $r('app.media.icon_nurse'), key: 'card_nurse' }, // 护士 -> nurse (记得改小写)
    { title: $r('app.string.menu_drug'), iconImg: $r('app.media.medical'), key: 'card_drug' }, // 用药 -> medical
    { title: $r('app.string.menu_order'), iconImg: $r('app.media.icon_order_manage'), key: 'card_order' }, // 订单 -> order_manage (记得改名)
    { title: $r('app.string.menu_rehab'), iconImg: $r('app.media.brain'), key: 'card_rehab' }, // 康复 -> brain
    { title: $r('app.string.menu_more'), iconImg: $r('app.media.more'), key: 'card_more' }, // 更多 -> more
  ];

  build() {
    Column() {
      // ============================================================
      // 1. 顶部导航栏 (返回键 + 个人信息 + 设置)
      // ============================================================
      Row() {
        // 左侧：返回按钮
        Button() {
          Image($r('app.media.icon_back')) // [需补充图片]
            .width(24).height(24)
            .fillColor(Color.White) // 如果是白色透明底图，不需要fillColor；如果是黑色svg需反白
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          NavigationModel.goBack(); // 调用返回逻辑
        })

        // 中间：空白撑开
        Blank()

        // 右侧：用户信息组
        Row({ space: 15 }) {
          // 姓名块
          Row({ space: 5 }) {
            Image($r('app.media.icon_user_small')) // [需补充图片] 小人图标
              .width(16).height(16)
              .objectFit(ImageFit.Contain)
            Text(this.userName)
              .fontSize(18)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }

          // 电话块
          Row({ space: 5 }) {
            Image($r('app.media.icon_phone_small')) // [需补充图片] 手机图标
              .width(16).height(16)
              .objectFit(ImageFit.Contain)
            Text(this.userPhone)
              .fontSize(16)
              .fontColor(Color.White)
          }

          // 设置按钮
          Image($r('app.media.icon_settings')) // [需补充图片] 设置图标
            .width(24).height(24)
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .height($r('app.float.header_height'))
      .padding({ left: 20, right: 20 })
      .backgroundColor($r('app.color.header_background')) // 深色底

      // ============================================================
      // 2. 主体布局 (响应式布局 + 滚动支持)
      // ============================================================
      Scroll() {
        GridRow({
          columns: 12,
          gutter: { x: 20, y: 20 },
          breakpoints: { value: ["600vp", "840vp"], reference: BreakpointsReference.WindowSize }
        }) {

          // --- 左侧列 (权重 2) ---
          GridCol({ span: { xs: 12, sm: 8, md: 8, lg: 8 } }) {
            Column() {
              // 2.1 顶部个人详情卡片
              Row() {
                // 头像
                Image($r('app.media.user_avatar')) // [需补充图片]
                  .width(60).height(60)
                  .borderRadius(30)
                  .margin({ right: 20 })

                Column({ space: 5 }) {
                  Text(this.userName).fontSize(22).fontColor(Color.White).fontWeight(FontWeight.Bold)
                  Row({ space: 10 }) {
                    Text(this.userGender).fontSize(14).fontColor(Color.White)
                    Text(`${this.userAge}岁`).fontSize(14).fontColor(Color.White)
                  }
                }.alignItems(HorizontalAlign.Start)

                Blank()

                Column({ space: 5 }) {

                }.alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding(20)
              // .backgroundColor($r('app.color.bg_card'))
              // 修改为：动态半透明背景 + 毛玻璃效果
              .backgroundColor(this.isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(255, 255, 255, 0.25)')
              .backdropBlur(20)
              .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.2)' })
              .borderRadius($r('app.float.card_radius'))
              .margin({ bottom: 20 })

              // 2.2 核心展示区 (悬浮气泡 + 右侧状态与呼叫)
              if (this.currentBreakpoint === 'xs') {
                // === 竖屏模式：列表展示 ===
                Column({ space: 15 }) {
                  // 1. 健康数据列表 (使用 Column 替代 List 以避免嵌套滚动冲突)
                  Column({ space: 10 }) {
                    this.HealthListItem("体温", `${this.tempVal}°C`, $r('app.media.icon_body_temperature'))
                    this.HealthListItem("心率", `${this.heartVal}次/min`, $r('app.media.icon_heart_rate'))
                    this.HealthListItem("血氧", `${this.spo2Val}%`, $r('app.media.icon_blood_oxygen'))
                    this.HealthListItem("血压", this.bpVal, $r('app.media.icon_pressure'))
                    this.HealthListItem("压力", this.stressVal, $r('app.media.heart_waves_fill'))
                  }
                  .width('100%')
                  // .height(320) // 移除固定高度，让其自适应

                  // 2. 状态显示 + 一键呼叫 (复用原有逻辑，但调整布局)
                  Column() {
                     // 用户身高体重信息
                     Column() {
                        Column({ space: 20 }) {
                          // 身高单独一行，左图标中文字右数值
                          Row() {
                            // 图标靠左
                            Image($r('app.media.icon_height')).width(35).height(35).margin({ right: 12 })
                            // 文字居中
                            Text("身高").fontSize(16).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.Center)
                            // 数值靠右
                            Text(`${this.userHeight}cm`).fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ left: 12 })
                          }.width('100%').height(40).alignItems(VerticalAlign.Center)
                          
                          // 体重单独一行，左图标中文字右数值
                          Row() {
                            // 图标靠左
                            Image($r('app.media.icon_weight')).width(35).height(35).margin({ right: 12 })
                            // 文字居中
                            Text("体重").fontSize(16).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.Center)
                            // 数值靠右
                            Text(`${this.userWeight}kg`).fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ left: 12 })
                          }.width('100%').height(40).alignItems(VerticalAlign.Center)
                          
                          // BMI单独一行，左图标中文字右数值
                          Row() {
                            // 图标靠左
                            Image($r('app.media.icon_BMI')).width(35).height(35).margin({ right: 12 })
                            // 文字居中
                            Text("BMI").fontSize(16).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.Center)
                            // 数值靠右
                            Text(this.userBMI === 0 ? '--' : `${this.userBMI}`).fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ left: 12 })
                          }.width('100%').height(40).alignItems(VerticalAlign.Center)
                        }
                     }
                     .padding({ left: 15, right: 15, top: 15, bottom: 10 })
                     .backgroundColor(this.isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(255, 255, 255, 0.25)')
                     .backdropBlur(20).border({ width: 0.5, color: 'rgba(255, 255, 255, 0.2)' }).borderRadius($r('app.float.card_radius'))
                     .width('90%')  // 放大宽度
                     .height(180)   // 放大高度
                     .margin({ top: 10, bottom: 10 }) // 可选：如果觉得太挤，可以加一点外边距
                     
                     // 空白区域，用于将一键呼叫按钮挤到最下方
                     Blank().layoutWeight(1)

                     // 一键呼叫
                     Button() {
                        Row({ space: 10 }) {
                          Image($r('app.media.icon_call_large')).width(32).height(32).fillColor(Color.White)
                          Text("一键呼叫").fontSize(22).fontColor(Color.White).fontWeight(FontWeight.Bold)
                        }
                     }
                     .width('100%').height(80)
                     .backgroundColor($r('app.color.btn_call_bg'))
                     .borderRadius($r('app.float.card_radius'))
                     .onClick(() => NavigationModel.handleJump('btn_one_key_call'))
                  }
                }
              } else {
                // === 横屏模式：原有气泡布局 ===
                Row({ space: 20 }) {
                  // A. 左侧：5个悬浮气泡 (替代3D模型)
                  Stack() {
                    // 气泡1：体温 (左上)
                    this.HealthBubble(`${this.tempVal}°C`, "体温", -110, -100)
                    // 气泡2：心率 (右上)
                    this.HealthBubble(`${this.heartVal}次`, "心率/min", 90, -110)
                    // 气泡3：血糖 (左中)
                    this.HealthBubble(`${this.spo2Val}%`, "血氧", -130, 20)
                    // 气泡4：血氧 (右中)
                    this.HealthBubble(this.bpVal, "血压", 110, 40)
                    // 气泡5：血压 (底部)
                    this.HealthBubble(this.stressVal, "压力", -20, 130)
                  }
                  .layoutWeight(1.5)
                  .height('100%')
                  .borderRadius($r('app.float.card_radius'))
                  .clip(true)

                  // B. 右侧：状态显示 + 一键呼叫
                  Column() {
                    // 上部分：用户身高体重信息
                    Column() {
                      Column({ space: 30 }) {
                        // 身高单独一行，左图标中文字右数值
                        Row() {
                          // 图标靠左
                          Image($r('app.media.icon_height')).width(40).height(40).margin({ right: 15 })
                          // 文字居中
                          Text("身高").fontSize(20).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.Center)
                          // 数值靠右
                          Text(`${this.userHeight}cm`).fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ left: 15 })
                        }.width('100%').height(50).alignItems(VerticalAlign.Center)
                        
                        // 体重单独一行，左图标中文字右数值
                        Row() {
                          // 图标靠左
                          Image($r('app.media.icon_weight')).width(40).height(40).margin({ right: 15 })
                          // 文字居中
                          Text("体重").fontSize(20).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.Center)
                          // 数值靠右
                          Text(`${this.userWeight}kg`).fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ left: 15 })
                        }.width('100%').height(50).alignItems(VerticalAlign.Center)
                        
                        // BMI单独一行，左图标中文字右数值
                        Row() {
                          // 图标靠左
                          Image($r('app.media.icon_BMI')).width(40).height(40).margin({ right: 15 })
                          // 文字居中
                          Text("BMI").fontSize(20).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.Center)
                          // 数值靠右
                          Text(this.userBMI === 0 ? '--' : `${this.userBMI}`).fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ left: 15 })
                        }.width('100%').height(50).alignItems(VerticalAlign.Center)
                      }
                    }

                    .width('100%')
                    .padding({ left: 15, right: 15, top: 15, bottom: 10 })
                    // .backgroundColor($r('app.color.bg_card'))
                    // 修改为：动态半透明背景 + 毛玻璃效果
                    .backgroundColor(this.isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(255, 255, 255, 0.25)')
                    .backdropBlur(20)
                    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.2)' })
                    .borderRadius($r('app.float.card_radius'))
                    .height(250)
                    .margin({ bottom: 20 })

                    // 空白区域，用于将一键呼叫按钮挤到最下方
                    Blank().layoutWeight(1)

                    // 下部分：一键呼叫 (大按钮)
                    Button() {
                      Row({ space: 10 }) {
                        Image($r('app.media.icon_call_large')) // [需补充]
                          .width(32).height(32)
                          .fillColor(Color.White)
                        Text("一键呼叫")
                          .fontSize(22)
                          .fontColor(Color.White)
                          .fontWeight(FontWeight.Bold)
                      }
                    }
                    .width('100%')
                    .height(100)
                    .backgroundColor($r('app.color.btn_call_bg')) // 红色背景
                    .borderRadius($r('app.float.card_radius'))
                    .onClick(() => {
                      // 调用接口：一键呼叫
                      NavigationModel.handleJump('btn_one_key_call');
                    })
                  }
                  .layoutWeight(1)
                  .height('100%')
                }
                .layoutWeight(1)
                .height('100%')
              }
            }
            .height(this.currentBreakpoint === 'xs' ? undefined : '100%')
          }

          // --- 右侧列 (Grid 菜单 - 使用你提供的10张图) ---
          GridCol({ span: { xs: 12, sm: 4, md: 4, lg: 4 } }) {
            Column() {
              if (this.currentBreakpoint === 'xs') {
                // 手机模式：使用 Flex 布局自动换行，避免 Grid 滚动冲突
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                  ForEach(this.menuList, (item: MenuItem) => {
                    Column() {
                      // 图标区域
                      Image(item.iconImg)
                        .width(48)
                        .height(48)
                        .objectFit(ImageFit.Contain)
                        .margin({ bottom: 10 })

                      Text(item.title)
                        .fontSize(16)
                        .fontColor(Color.White)
                    }
                    .width('48%') // 2列，留间隙
                    .height(120)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(this.isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(255, 255, 255, 0.25)')
                    .backdropBlur(20)
                    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.2)' })
                    .borderRadius($r('app.float.card_radius'))
                    .margin({ bottom: 12 })
                    .onClick(() => {
                      NavigationModel.handleJump(item.key);
                    })
                  })
                }
                .width('100%')
              } else {
                // 平板/大屏模式：使用 Grid
                Grid() {
                  ForEach(this.menuList, (item: MenuItem) => {
                    GridItem() {
                      Column() {
                        // 图标区域
                        Image(item.iconImg)
                          .width(48)
                          .height(48)
                          .objectFit(ImageFit.Contain)
                          .margin({ bottom: 10 })

                        Text(item.title)
                          .fontSize(16)
                          .fontColor(Color.White)
                      }
                      .width('100%').height('100%')
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor(this.isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(255, 255, 255, 0.25)')
                      .backdropBlur(20)
                      .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.2)' })
                      .borderRadius($r('app.float.card_radius'))
                      .onClick(() => {
                        NavigationModel.handleJump(item.key);
                      })
                    }
                  })
                }
                .columnsTemplate('1fr 1fr') // 2 列
                .rowsTemplate('1fr 1fr 1fr 1fr 1fr') // 5 行
                .rowsGap(12).columnsGap(12)
                .width('100%')
                .height('100%')
              }
            }
            .height(this.currentBreakpoint === 'xs' ? undefined : '100%')
          }
        }
        .key('GridRow_' + this.uiRefresher) // 强制 GridRow 重新渲染
        .onBreakpointChange((breakpoint: string) => {
          this.currentBreakpoint = breakpoint;
        })
        .width('100%')
        .height(this.currentBreakpoint === 'xs' ? undefined : '100%') // 手机模式下高度自适应
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page')) // 全局深色背景
    .backgroundImage($r('app.media.bg_wellness'))
    .backgroundImageSize(ImageSize.Cover)
  }

  // --- 列表项构建函数 (竖屏用) ---
  @Builder HealthListItem(label: string, value: string, icon: Resource) {
    Row() {
      Image(icon).width(24).height(24).fillColor(Color.White).margin({ right: 10 })
      Text(label).fontSize(16).fontColor(Color.White)
      Blank()
      Text(value).fontSize(18).fontColor($r('app.color.text_cyan')).fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .padding(15)
    .backgroundColor(this.isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(255, 255, 255, 0.25)')
    .backdropBlur(20)
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.2)' })
    .borderRadius($r('app.float.card_radius'))
  }

  // --- 气泡构建函数 (横屏用) ---
  @Builder HealthBubble(value: string, label: string, x: number, y: number) {
    Column() {
      // 增加判空显示，如果为0或空则显示 --
      Text((value === '0' || value === '0.0°C' || value === '0%' || value === '0/0') ? '--' : value)
        .fontSize(20)
        .fontColor($r('app.color.text_cyan'))
        .fontWeight(FontWeight.Bold)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_gray'))
    }
    .width(90)
    .height(90)
    .borderRadius(45)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bubble_bg')) // 半透明黑底
    .border({ width: 1, color: $r('app.color.bubble_border') }) // 蓝色描边
    .shadow({ radius: 10, color: $r('app.color.bubble_border') }) // 发光效果
    .offset({ x: x, y: y }) // 绝对定位偏移
  }
}