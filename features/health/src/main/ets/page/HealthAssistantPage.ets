import router from '@ohos.router';
import { UserRepo, UserProfile, UserInfo } from 'auth';
import { AiService } from '../utils/AiService';
import { relationalStore } from '@kit.ArkData';
import { AppDatabase } from 'utils';
import { HealthDataService, HealthRecord } from '../database/HealthDataService';

interface ChatMessage {
  id: number;
  role: 'user' | 'ai';
  content: string;
}

@Entry({ routeName: 'HealthAssistantPage' })
@Component
export struct HealthAssistantPage {
  @State messageList: ChatMessage[] = [];
  @State inputText: string = '';
  @State isTyping: boolean = false;
  @State userProfile: UserProfile | null = null;
  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    this.loadUserProfile();
    // 初始欢迎语
    this.addAiMessage("你好！我是你的健康小助手。我可以根据你的身体数据为你提供健康建议。");
  }

  async loadUserProfile() {
    const currentUser = AppStorage.get<UserInfo>('currentUser');
    if (currentUser) {
      try {
        const profile = await UserRepo.getUserProfile(currentUser.id);
        if (profile) {
          this.userProfile = profile;
          // 可以在这里根据画像主动发起第一轮分析
          this.analyzeHealthInitial();
        }
      } catch (e) {
        console.error('加载用户画像失败:', JSON.stringify(e));
      }
    }
  }

  analyzeHealthInitial() {
    if (!this.userProfile) return;
    
    let info = `我看到你的档案：${this.userProfile.gender}性，${this.userProfile.age}岁`;
    if (this.userProfile.height && this.userProfile.weight) {
      info += `，身高${this.userProfile.height}cm，体重${this.userProfile.weight}kg。`;
      // 简单的 BMI 计算
      const heightM = this.userProfile.height / 100;
      const bmi = this.userProfile.weight / (heightM * heightM);
      info += `\n你的BMI指数为：${bmi.toFixed(1)}。`;
    }
    this.addAiMessage(info + "\n有什么我可以帮你的吗？");
  }

  addAiMessage(content: string) {
    this.messageList.push({
      id: Date.now(),
      role: 'ai',
      content: content
    });
    this.scrollToBottom();
  }

  addUserMessage(content: string) {
    this.messageList.push({
      id: Date.now(),
      role: 'user',
      content: content
    });
    this.scrollToBottom();
  }

  scrollToBottom() {
    // 简单延时确保列表渲染后滚动
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  async getFullContext(): Promise<string> {
    let context = "";

    // 1. 用户画像
    if (this.userProfile) {
      context += `[用户画像]
      性别：${this.userProfile.gender}
      年龄：${this.userProfile.age}
      身高：${this.userProfile.height}cm
      体重：${this.userProfile.weight}kg\n`;
    }

    // 2. 今日健康数据
    try {
      const todayStr: string = HealthDataService.formatDate(new Date());
      const healthRecord: HealthRecord | null = await HealthDataService.getHealthDataByDate(todayStr);
      if (healthRecord) {
        context += `[今日健康数据]
        步数：${healthRecord.stepsCurrent}
        心率：${healthRecord.heartRate} bpm
        血压：${healthRecord.bpSystolic}/${healthRecord.bpDiastolic} mmHg
        体温：${healthRecord.temperature}°C
        压力值：${healthRecord.stressValue}
        睡眠：${healthRecord.sleepTotal}小时
        血氧：${healthRecord.spo2}%\n`;
      }
    } catch (e) {
      console.warn('获取健康数据失败', JSON.stringify(e));
    }

    // 3. 家庭环境与网络 (直接查询数据库)
    try {
      const store = AppDatabase.getStore();
      if (store) {
        const predicates = new relationalStore.RdbPredicates('house_metrics');
        
        // 增加用户ID过滤，防止读取到其他用户的数据
        const currentUser = AppStorage.get<UserInfo>('currentUser');
        if (currentUser) {
          predicates.equalTo('user_id', currentUser.id);
        }
        
        predicates.orderByDesc('ts');
        predicates.limitAs(1);
        
        const resultSet: relationalStore.ResultSet = await store.query(predicates);
        if (resultSet.goToFirstRow()) {
          const energy: number = resultSet.getDouble(resultSet.getColumnIndex('energy_kwh'));
          const co2: number = resultSet.getDouble(resultSet.getColumnIndex('co2_ppm'));
          const down: number = resultSet.getDouble(resultSet.getColumnIndex('net_down_mbps'));
          
          context += `[家庭环境]
          今日能耗：${energy.toFixed(1)} kWh
          CO2浓度：${co2.toFixed(0)} ppm
          网络下载速度：${down.toFixed(0)} Mbps\n`;
        }
        resultSet.close();
      }
    } catch (e) {
      console.warn('获取环境数据失败', JSON.stringify(e));
    }

    return context;
  }

  async sendMessage() {
    if (!this.inputText.trim()) return;

    const text = this.inputText;
    this.inputText = ''; // 清空输入框
    this.addUserMessage(text);

    this.isTyping = true;

    // --- 构造系统人设 (Context) ---
    let systemPrompt = "你是一个专业的家庭健康助手。";
    
    // 获取完整的上下文数据 (DB + UserProfile)
    const contextData = await this.getFullContext();
    if (contextData) {
      systemPrompt += `\n当前用户的实时状态如下：\n${contextData}\n请根据这些数据回答用户的健康或家庭环境问题，回答要亲切、专业且简短。`;
    }

    // --- 调用真实 API ---
    try {
      const aiReply = await AiService.chatWithAi(text, systemPrompt);
      this.isTyping = false;
      this.addAiMessage(aiReply);
    } catch (e) {
      this.isTyping = false;
      this.addAiMessage("抱歉，我遇到了一点小问题，请稍后再试。");
    }
  }

  mockAiResponse(userText: string) {
    let reply = "收到，这是一个很好的问题。";
    if (userText.includes("运动")) {
      reply = "根据你的年龄和体重，我建议你每周进行至少150分钟的中等强度有氧运动，比如快走或游泳。";
    } else if (userText.includes("饮食") || userText.includes("吃")) {
      reply = "建议保持均衡饮食，多摄入蔬菜水果，减少高糖高油食物的摄入。";
    } else {
      reply = "我现在还在学习中，稍后我会接入更强大的大脑来回答你的问题！(API 预留位)";
    }
    this.addAiMessage(reply);
  }

  build() {
    Column() {
      // 1. 标题栏
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))//系统内置图标
          .fontSize(24)
          .fontColor([$r('app.color.text_white')])
          .onClick(() => router.back())
        Text("健康小助手")
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_white')) // 适配深色模式
          .margin({ left: 15 })
      }
      .width('100%')
      .padding(15)
      .backgroundColor($r('app.color.bg_card'))
      .shadow({ radius: 2, color: 'rgba(0,0,0,0.1)', offsetY: 2 })

      // 2. 聊天列表
      List({ scroller: this.scroller, space: 15 }) {
        ForEach(this.messageList, (msg: ChatMessage) => {
          ListItem() {
            Row() {
              if (msg.role === 'ai') {
                // AI 头像
                Image($r('app.media.icon_heart_rate')) // 假设有个健康图标，或者用通用图标
                  .width(40).height(40)
                  .backgroundColor($r('app.color.bubble_bg'))
                  .borderRadius(20)
                  .padding(8)
                  .margin({ right: 10 })
                
                // AI 消息气泡
                Text(msg.content)
                  .fontSize(16)
                  .fontColor($r('app.color.text_white')) // 适配深色模式
                  .backgroundColor($r('app.color.bubble_bg'))
                  .padding(12)
                  .borderRadius({ topLeft: 0, topRight: 12, bottomLeft: 12, bottomRight: 12 })
                  .layoutWeight(1)
                  .shadow({ radius: 2, color: 'rgba(0,0,0,0.05)' })
              } else {
                // 用户消息气泡 (右侧)
                Blank()
                Text(msg.content)
                  .fontSize(16)
                  .fontColor(Color.White)
                  .backgroundColor('#007DFF')
                  .padding(12)
                  .borderRadius({ topLeft: 12, topRight: 0, bottomLeft: 12, bottomRight: 12 })
                  .margin({ right: 10 })
                  .constraintSize({ maxWidth: '70%' })
                
                // 用户头像
                Image($r('app.media.user_icon'))
                  .width(40).height(40)
                  .borderRadius(20)
                  .backgroundColor($r('app.color.bg_icon_container'))
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .justifyContent(msg.role === 'ai' ? FlexAlign.Start : FlexAlign.End)
          }
        }, (msg: ChatMessage) => msg.id.toString())
      }
      .layoutWeight(1)
      .width('100%')
      .padding(15)
      .backgroundColor($r('app.color.bg_page'))

      // 3. 输入区
      Row() {
        TextInput({ placeholder: '请输入你的健康问题...', text: this.inputText })
          .layoutWeight(1)
          .height(40)
          .fontColor($r('app.color.text_white')) // 适配深色模式
          .placeholderColor($r('app.color.text_gray')) // 适配深色模式
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(20)
          .padding({ left: 15, right: 15 })
          .onChange((value) => this.inputText = value)
          .onSubmit(() => this.sendMessage())

        Button("发送")
          .height(40)
          .margin({ left: 10 })
          .onClick(() => this.sendMessage())
          .enabled(!this.isTyping)
      }
      .width('100%')
      .padding(10)
      .backgroundColor($r('app.color.bg_card'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page')) // 确保根容器也有背景色
  }
}
