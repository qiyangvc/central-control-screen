import { router, promptAction } from '@kit.ArkUI';
import { UserRepo } from '../model/UserRepo';

@Component
export struct LoginPage {
  // 状态变量
  @State account: string = '';
  @State pass: string = '';
  @State isRegister: boolean = false; // 默认为登录模式

  // --- 样式定义 ---
  // 统一的输入框样式：固定宽度 320vp，适配手机和平板
  @Styles inputStyle() {
    .width(320)
    .height(50)
    .backgroundColor('#F5F7FA') // 浅灰背景
    .borderRadius(12) // 柔和圆角
    .padding({ left: 15, right: 15 })
  }

  // --- 业务逻辑 ---
  async handleAction() {
    // 1. 基础校验
    if (!this.account || !this.pass) {
      promptAction.showToast({ message: '请输入完整信息', bottom: 500 });
      return;
    }

    if (this.isRegister) {
      // === 注册流程 ===
      try {
        const success = await UserRepo.register(this.account, this.pass);
        if (success) {
          promptAction.showToast({ message: '注册成功，请登录', bottom: 500 });
          // 注册成功后，自动切回登录模式，并清空密码
          this.isRegister = false;
          this.pass = '';
        } else {
          promptAction.showToast({ message: '该账号已存在', bottom: 500 });
        }
      } catch (err) {
        console.error('注册失败:', err);
        promptAction.showToast({ message: '系统繁忙，请稍后再试', bottom: 500 });
      }

    } else {
      // === 登录流程 ===
      try {
        const user = await UserRepo.login(this.account, this.pass);
        if (user) {
          // 登录成功
          promptAction.showToast({ message: '欢迎回来，' + user.name, bottom: 500 });

          // 1. 保存用户信息到全局存储 (方便其他页面使用)
          AppStorage.setOrCreate('currentUser', user);
          AppStorage.setOrCreate('currentUserId', user.id);

          // 2. 跳转到主页 (使用 replaceUrl 销毁当前登录页，防止用户点返回键回来)
          router.replaceUrl({ url: 'pages/Index' });
        } else {
          promptAction.showToast({ message: '账号或密码错误', bottom: 500 });
        }
      } catch (err) {
        console.error('登录失败:', err);
        promptAction.showToast({ message: '系统错误', bottom: 500 });
      }
    }
  }

  // --- 界面构建 ---
  build() {
    Stack() {
      // 1. 背景层：清新的蓝白渐变
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [[0xE6F2FF, 0.0], [0xFFFFFF, 0.6]] // 上浅蓝，下白
        })

      // 2. 内容层 (居中显示)
      Column() {

        // --- Logo / 标题区域 ---
        Column({ space: 10 }) {
          // [Logo]
          Image($r('app.media.app_icon'))
            .width(80)
            .height(80)
            .borderRadius(20)
            .shadow({ radius: 10, color: 'rgba(0,0,0,0.1)', offsetY: 5 })
            .margin({ bottom: 10 })

          // [占位 Logo]
          // Text("Logo")
          //   .fontSize(20)
          //   .fontColor('#007DFF')
          //   .fontWeight(FontWeight.Bold)
          //   .width(80)
          //   .height(80)
          //   .borderRadius(20)
          //   .backgroundColor('rgba(255,255,255,0.8)')
          //   .textAlign(TextAlign.Center)
          //   .shadow({ radius: 10, color: 'rgba(0,0,0,0.1)', offsetY: 5 })
          //   .margin({ bottom: 10 })

          // 主标题
          Text(this.isRegister ? '创建新账户' : '欢迎回来')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')

          // 副标题
          Text(this.isRegister ? '注册以体验智慧医疗服务' : '登录您的中控屏管理系统')
            .fontSize(14)
            .fontColor('#999999')
        }
        .margin({ top: 80, bottom: 40 }) // 距离顶部的距离

        // --- 核心操作卡片 ---
        Column({ space: 20 }) {

          // 1. 账号输入框
          TextInput({ placeholder: '请输入账号', text: this.account })
            .inputStyle() // 使用定义的固定宽度样式
            .onChange(v => this.account = v)
            .placeholderColor('#B0B0B0')

          // 2. 密码输入框
          TextInput({ placeholder: '请输入密码', text: this.pass })
            .type(InputType.Password) // 密码模式
            .inputStyle() // 使用定义的固定宽度样式
            .onChange(v => this.pass = v)
            .placeholderColor('#B0B0B0')

          // 3. 登录/注册按钮
          Button(this.isRegister ? '立即注册' : '登 录')
            .width(320) // 按钮宽度与输入框保持一致
            .height(50)
            .borderRadius(25) // 全圆角
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .shadow({ radius: 15, color: 'rgba(0, 125, 255, 0.3)', offsetY: 5 }) // 蓝色投影
            .linearGradient({
              angle: 90,
              colors: [[0x007DFF, 0.0], [0x0057D9, 1.0]] // 按钮渐变色
            })
            .onClick(() => {
              this.handleAction()
            })

          // 4. 底部切换模式链接
          Row() {
            Text(this.isRegister ? '已有账号？' : '还没有账号？')
              .fontColor('#999999')
              .fontSize(14)

            Text(this.isRegister ? '去登录' : '去注册')
              .fontColor('#007DFF') // 品牌主色
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .padding({ left: 5, top: 10, bottom: 10 }) // 增加点击热区
              .onClick(() => {
                // 切换动画效果
                animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                  this.isRegister = !this.isRegister;
                  // 切换时清空密码，提升体验
                  this.pass = '';
                })
              })
          }
          .margin({ top: 10 })

        }
        .backgroundColor('#FFFFFF') // 卡片白色背景
        .borderRadius(24) // 卡片圆角
        .padding({ top: 40, bottom: 40, left: 40, right: 40 }) // 内部间距
        .shadow({ radius: 30, color: 'rgba(0,0,0,0.05)', offsetY: 10 }) // 卡片阴影

      }
      .width('100%') // 内容层宽度占满屏幕
    }
    .height('100%') // 整个页面高度占满
  }
}