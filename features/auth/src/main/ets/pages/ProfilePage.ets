import { router, promptAction } from '@kit.ArkUI';
import { UserRepo, UserProfile, UserInfo } from '../model/UserRepo';
@Preview
@Entry({ routeName: 'ProfilePage' })
@Component
export struct ProfilePage {
  @State profile: UserProfile = {
    userId: 0,
    name: '',
    phone: '',
    height: 0,
    weight: 0,
    age: 0,
    gender: '未知',
    targetSteps: 10000,
    targetCalories: 500
  };
  @State isLoading: boolean = true;

  async aboutToAppear() {
    // 获取当前登录用户
    const currentUser = AppStorage.get<UserInfo>('currentUser');
    if (!currentUser) {
      promptAction.showToast({ message: '未登录' });
      router.back();
      return;
    }

    // 加载数据
    this.profile = await UserRepo.getUserProfile(currentUser.id);
    this.isLoading = false;
  }

  async handleSave() {
    if (!this.profile.name) {
      promptAction.showToast({ message: '姓名不能为空' });
      return;
    }
    
    const success = await UserRepo.updateUserProfile(this.profile);
    if (success) {
      promptAction.showToast({ message: '保存成功' });
      // 更新全局存储中的名字，以便主页等地方同步更新
      const currentUser = AppStorage.get<UserInfo>('currentUser');
      if (currentUser) {
        currentUser.name = this.profile.name;
        AppStorage.setOrCreate('currentUser', currentUser);
      }
      // ⚡️ 通知 HealthSportsPage 刷新数据
      AppStorage.setOrCreate('HealthDataLastUpdate', Date.now());
      // ⚡️ 更新全局目标设置 (用于其他页面即时显示)
      AppStorage.setOrCreate('targetSteps', this.profile.targetSteps);
      AppStorage.setOrCreate('targetCalories', this.profile.targetCalories);
      
      router.back();
    } else {
      promptAction.showToast({ message: '保存失败' });
    }
  }

  handleLogout() {
    // 清除登录状态
    AppStorage.setOrCreate('currentUser', undefined);
    AppStorage.setOrCreate('currentUserId', 0);
    // 返回登录页 (注意：这里假设登录页是入口，或者需要跳转到登录页)
    // 由于我们是 router.push 进来的，最好是 replace 到登录页，或者 back 到主页然后主页判断未登录跳转
    // 简单起见，直接跳转到登录页并清空栈
    router.clear();
    router.replaceUrl({ url: 'pages/LoginPage' });
  }

  @Styles inputStyle() {
    .width('100%')
    .height(40)
    .backgroundColor($r('app.color.input_bg'))
    .borderRadius(8)
    .padding({ left: 10 })
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))//系统内置图标
          .fontSize(24)
          .fontColor([$r('app.color.text_primary')])
          .onClick(() => router.back())
        
        Text('个人信息')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          
        Blank().width(24)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.bg_page'))

      if (this.isLoading) {
        LoadingProgress().width(50).height(50).margin({ top: 100 })
      } else {
        Scroll() {
          Column({ space: 20 }) {
            // ID (不可修改)
            Column({ space: 8 }) {
              Text('用户 ID').fontSize(14).fontColor($r('app.color.text_secondary'))
              Text(this.profile.userId.toString())
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .padding({ left: 10 })
            }.alignItems(HorizontalAlign.Start).width('100%')

            // 姓名
            Column({ space: 8 }) {
              Text('姓名').fontSize(14).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.profile.name, placeholder: '请输入姓名' })
                .onChange((val) => this.profile.name = val)
                .inputStyle()
                .fontColor($r('app.color.text_primary'))
            }.alignItems(HorizontalAlign.Start).width('100%')

            // 手机号
            Column({ space: 8 }) {
              Text('手机号').fontSize(14).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.profile.phone, placeholder: '请输入手机号' })
                .onChange((val) => this.profile.phone = val)
                .inputStyle()
                .fontColor($r('app.color.text_primary'))
            }.alignItems(HorizontalAlign.Start).width('100%')

            // 🎯 目标设置 (本地存储)
            Row() {
              Column({ space: 8 }) {
                Text('目标步数').fontSize(14).fontColor($r('app.color.text_secondary'))
                TextInput({ text: this.profile.targetSteps.toString(), placeholder: '10000' })
                  .type(InputType.Number)
                  .onChange((val) => this.profile.targetSteps = parseInt(val) || 0)
                  .inputStyle()
                  .fontColor($r('app.color.text_primary'))
              }.layoutWeight(1).margin({ right: 10 })

              Column({ space: 8 }) {
                Text('目标热量 (kcal)').fontSize(14).fontColor($r('app.color.text_secondary'))
                TextInput({ text: this.profile.targetCalories.toString(), placeholder: '500' })
                  .type(InputType.Number)
                  .onChange((val) => this.profile.targetCalories = parseInt(val) || 0)
                  .inputStyle()
                  .fontColor($r('app.color.text_primary'))
              }.layoutWeight(1).margin({ left: 10 })
            }.width('100%')

            // 年龄
            Column({ space: 8 }) {
              Text('年龄').fontSize(14).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.profile.age ? this.profile.age.toString() : '', placeholder: '0' })
                .type(InputType.Number)
                .onChange((val) => this.profile.age = parseInt(val) || 0)
                .inputStyle()
                .fontColor($r('app.color.text_primary'))
            }.alignItems(HorizontalAlign.Start).width('100%')

            // 性别
            Column({ space: 8 }) {
              Text('性别').fontSize(14).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.profile.gender, placeholder: '男/女' })
                .onChange((val) => this.profile.gender = val)
                .inputStyle()
                .fontColor($r('app.color.text_primary'))
            }.alignItems(HorizontalAlign.Start).width('100%')

            // 身高
            Column({ space: 8 }) {
              Text('身高 (cm)').fontSize(14).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.profile.height ? this.profile.height.toString() : '', placeholder: '0' })
                .type(InputType.Number)
                .onChange((val) => this.profile.height = parseFloat(val) || 0)
                .inputStyle()
                .fontColor($r('app.color.text_primary'))
            }.alignItems(HorizontalAlign.Start).width('100%')

            // 体重
            Column({ space: 8 }) {
              Text('体重 (kg)').fontSize(14).fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.profile.weight ? this.profile.weight.toString() : '', placeholder: '0' })
                .type(InputType.Number)
                .onChange((val) => this.profile.weight = parseFloat(val) || 0)
                .inputStyle()
                .fontColor($r('app.color.text_primary'))
            }.alignItems(HorizontalAlign.Start).width('100%')

            // 保存按钮
            Button('保存修改')
              .width('100%')
              .height(45)
              .fontSize(16)
              .type(ButtonType.Capsule)
              .margin({ top: 20 })
              .onClick(() => this.handleSave())

            // 退出登录
            Button('退出登录')
              .width('100%')
              .height(45)
              .fontSize(16)
              .fontColor(Color.Red)
              .backgroundColor($r('app.color.bg_danger_light'))
              .type(ButtonType.Capsule)
              .margin({ top: 10 })
              .onClick(() => this.handleLogout())

          }
          .width('100%')
          .constraintSize({ maxWidth: 600 }) // 适配平板：限制最大宽度，避免过长
          .padding({ left: 20, right: 20, top: 20, bottom: 20 }) // 适配手机：保持基础边距
        }
        .layoutWeight(1)
        .align(Alignment.Top) // 适配：内容水平居中
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
