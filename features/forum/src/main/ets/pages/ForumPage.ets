import { ForumService } from '../service/ForumService';
import { ForumPost, UserInfo, PostDetailData, ProfileData, Comment, ApiResponse } from '../model/ForumModel';
import { promptAction } from '@kit.ArkUI';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { request } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

// 🔴 确认 IP 地址
// const DOMAIN = 'http://172.26.117.216:8000';
const DOMAIN = 'http://172.26.23.157:8000';

// ⚡️ 图片 URL 处理工具 (强力修复版)
function getImageUrl(url: string): string {
  if (!url) return '';

  // 1. 如果是 Base64 数据，直接返回
  if (url.startsWith('data:')) return url;

  // 2. 核心逻辑：只要 URL 中包含 "uploads/"，就强制替换前面的域名/IP
  // 这能解决 IP 变动、localhost、10.0.2.2 等所有历史遗留问题
  const keyword = 'uploads/';
  const index = url.indexOf(keyword);
  
  if (index >= 0) {
    // 提取从 uploads/ 开始的路径 (例如 "uploads/abc.jpg")
    let relativePath = url.substring(index);
    return `${DOMAIN}/${relativePath}`;
  }

  // 3. 如果不包含 uploads/ 但已经是 http 开头（外链），则保留
  if (url.startsWith('http')) return url;

  // 4. 剩下的情况认为是相对路径或纯文件名
  let cleanPath = url;
  // 去除开头的 /
  while (cleanPath.startsWith('/')) {
    cleanPath = cleanPath.substring(1);
  }

  // 如果看起来像文件名，补全 uploads/
  if (!cleanPath.includes('/') && (cleanPath.endsWith('.jpg') || cleanPath.endsWith('.png') || cleanPath.endsWith('.jpeg'))) {
    cleanPath = `uploads/${cleanPath}`;
  }

  return `${DOMAIN}/${cleanPath}`;
}

class PostParams {
  id: number = 0
  constructor(id: number) { this.id = id }
}

class PublishParams {
  postId?: number
  title?: string
  content?: string
  tags?: string
  images?: string[]
}

class SearchParams {
  keyword: string = ''
  constructor(keyword: string) { this.keyword = keyword }
}

AppStorage.setOrCreate('currentUserId', 0);
AppStorage.setOrCreate('refreshFeed', 0);

@Entry({ routeName: 'HealthForumPage' })
@Component
export struct ForumPage {
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();
  @State currentIndex: number = 0;
  @StorageLink('currentUserId') currentUserId: number = 0;

  build() {
    Navigation(this.pageStack) {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
        TabContent() { HomePage() }.tabBar(this.TabBuilder('首页', 0, $r('app.media.ic_public_home')))
        TabContent() {}.tabBar(this.AddBtnBuilder())
        TabContent() {
          if (this.currentUserId > 0) ProfileView({ userId: this.currentUserId, isSelf: true })
          else LoginView()
        }.tabBar(this.TabBuilder('我的', 2, $r('app.media.ic_public_contacts')))
      }
      .onChange((index) => {
        if (index === 1) {
          if (this.currentUserId === 0) {
            promptAction.showToast({message: '请先登录'});
            this.currentIndex = 2;
          } else {
            // 修复：使用 setTimeout 确保状态更新不会冲突，并强制重置 currentIndex
            setTimeout(() => {
              this.pageStack.pushPath({ name: 'PublishPage' });
              this.currentIndex = 0;
            }, 10);
          }
        } else {
          this.currentIndex = index;
        }
      })
      .barHeight(56)
    }
    .mode(NavigationMode.Stack)
    .navDestination(this.PagesMap)
    .hideTitleBar(true)
  }

  @Builder PagesMap(name: string, param: object) {
    if (name === 'PostDetail') PostDetailView({ postId: (param as PostParams).id })
    else if (name === 'PublishPage') {
      PublishView({
        editPostId: (param as PublishParams)?.postId || 0,
        title: (param as PublishParams)?.title || '',
        content: (param as PublishParams)?.content || '',
        tags: (param as PublishParams)?.tags || '',
        uploadedUrls: (param as PublishParams)?.images || []
      })
    }
    else if (name === 'UserProfile') ProfileView({ userId: (param as PostParams).id, isSelf: false })
    else if (name === 'SearchPage') SearchPage({ keyword: (param as SearchParams).keyword })
  }

  @Builder TabBuilder(title: string, index: number, icon: Resource) {
    Column() {
      // 这里的 fillColor 可以留着，因为底部 Tab 图标通常是简单的 SVG
      Image(icon).width(24).fillColor(this.currentIndex === index ? $r('app.color.brand_red') : $r('app.color.text_secondary'))
      Text(title).fontSize(10).fontColor(this.currentIndex === index ? $r('app.color.brand_red') : $r('app.color.text_secondary')).margin({top:2})
    }.justifyContent(FlexAlign.Center).height('100%')
  }

  @Builder AddBtnBuilder() {
    Column() {
      Stack() {
        // 背景圆圈，确保在任何模式下都有对比度
        Circle().width(40).height(40).fill($r('app.color.bg_card'))
        // 图标
        Image($r('app.media.ic_public_add'))
          .width(38).height(38)
          .fillColor($r('app.color.brand_red'))
      }
      .margin({top: 5})
    }.height('100%').justifyContent(FlexAlign.Center)
  }
}

// ===================== 首页 (修复自动刷新 + 瀑布流) =====================
@Component
struct HomePage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State posts: ForumPost[] = [];
  @State searchText: string = '';
  @State isLoading: boolean = false; // 加载状态
  @State sortType: number = 0; // 0: 推荐, 1: 最新, 2: 最热, 3: 最多收藏
  @State userTags: string[] = []; // 用户画像标签
  private allPostsCache: ForumPost[] = []; // 本地缓存全量数据

  @StorageProp('refreshFeed') @Watch('loadData') refreshSignal: number = 0;
  @StorageProp('postUpdate') @Watch('onPostUpdate') postUpdateSignal: Record<string, Object> = {};
  // ⚡️ 修复：监听用户登录状态变化，登录后自动刷新列表以获取正确的点赞/收藏状态
  @StorageLink('currentUserId') @Watch('onUserChange') currentUserId: number = 0;

  async onUserChange() {
    await this.fetchUserTags();
    this.loadData();
  }

  onPostUpdate() {
    const update = this.postUpdateSignal;
    if (!update || !update['id']) return;

    const id = update['id'] as number;
    // 更新 posts 数组中的对应项
    const index = this.posts.findIndex(p => p.id === id);
    if (index !== -1) {
      this.posts[index].like_count = update['like_count'] as number;
      this.posts[index].is_liked = update['is_liked'] as number;
      this.posts[index].fav_count = update['fav_count'] as number;
      this.posts[index].is_faved = update['is_faved'] as number;
      
      // 强制刷新数组以触发UI更新
      this.posts = [...this.posts];
    }
    
    // 同时也更新缓存
    const cacheIndex = this.allPostsCache.findIndex(p => p.id === id);
    if (cacheIndex !== -1) {
      this.allPostsCache[cacheIndex].like_count = update['like_count'] as number;
      this.allPostsCache[cacheIndex].is_liked = update['is_liked'] as number;
      this.allPostsCache[cacheIndex].fav_count = update['fav_count'] as number;
      this.allPostsCache[cacheIndex].is_faved = update['is_faved'] as number;
    }
  }

  // ⚡️ 修复1：组件一加载就拉数据
  async aboutToAppear() {
    await this.fetchUserTags();
    this.loadData();
  }

  // ⚡️ 修复2：页面每次显示也检查数据（双重保险）
  onPageShow() {
    if (this.posts.length === 0) {
      this.loadData();
    }
  }

  // 获取用户标签用于推荐算法
  async fetchUserTags() {
    const uid = AppStorage.get<number>('currentUserId');
    if (uid) {
      const res = await ForumService.getProfile(uid);
      if (res.success && res.data && res.data.info.health_tags) {
         // 拆分标签：支持空格、逗号
         this.userTags = res.data.info.health_tags.split(/[,，\s]+/).filter(t => t.trim() !== '');
      }
    }
  }

  async loadData() {
    this.isLoading = true;
    // 临时方案：前端过滤，确保Tag搜索生效 (因为后端搜索可能不包含Tag)
    // 1. 获取所有数据 (传空字符串)
    const res = await ForumService.getFeed(""); 
    this.isLoading = false;
    
    if (res.success && res.data) {
      // 2. 数据清洗
      this.allPostsCache = res.data.map(item => {
        if (typeof item.images === 'string') {
          try { item.images = JSON.parse(item.images); } catch(e) { item.images = []; }
        }
        if (typeof item.tags === 'string') {
          try { 
            item.tags = JSON.parse(item.tags); 
          } catch(e) { 
            // ⚡️ 修复：如果JSON解析失败，尝试按空格或逗号分割
            if (typeof item.tags === 'string') {
                item.tags = (item.tags as string).split(/[,，\s]+/).filter(t => t.trim() !== '');
            } else {
                item.tags = []; 
            }
          }
        }
        return item;
      });
      
      // 3. 刷新列表显示
      this.refreshList();
    }
  }

  // 计算帖子与用户标签的匹配度
  calculateMatchScore(post: ForumPost): number {
    if (this.userTags.length === 0) return 0;
    let score = 0;
    
    // 1. 标签匹配 (权重高)
    if (post.tags && Array.isArray(post.tags)) {
        post.tags.forEach(tag => {
            // 模糊匹配：只要包含即可
            if (this.userTags.some(uTag => tag.toLowerCase().includes(uTag.toLowerCase()) || uTag.toLowerCase().includes(tag.toLowerCase()))) {
                score += 5; 
            }
        });
    }

    // 2. 标题和内容匹配 (权重低，作为补充)
    // 这样即使帖子没有打标签，只要标题或内容里提到了相关词，也能被推荐
    const fullText = ((post.title || '') + (post.content || '')).toLowerCase();
    this.userTags.forEach(uTag => {
        const t = uTag.toLowerCase();
        if (fullText.includes(t)) {
            score += 1;
        }
    });

    return score;
  }

  // 统一处理过滤和排序
  refreshList() {
    let result = [...this.allPostsCache]; // 浅拷贝，避免影响原数组顺序

    // A. 过滤
    if (this.searchText && this.searchText.trim().length > 0) {
      const keyword = this.searchText.toLowerCase().trim();
      result = result.filter(post => {
        const matchTitle = post.title && post.title.toLowerCase().includes(keyword);
        const matchContent = post.content && post.content.toLowerCase().includes(keyword);
        const matchTags = post.tags && Array.isArray(post.tags) && post.tags.some(tag => tag.toLowerCase().includes(keyword));
        return matchTitle || matchContent || matchTags;
      });
    }

    // B. 排序
    if (this.sortType === 0) {
      // 推荐：按标签匹配度倒序 -> ID倒序
      result.sort((a, b) => {
        const scoreA = this.calculateMatchScore(a);
        const scoreB = this.calculateMatchScore(b);
        if (scoreA !== scoreB) return scoreB - scoreA; // 分数高的在前
        return b.id - a.id; // 分数相同，新的在前
      });
    } else if (this.sortType === 1) {
      // 最新：按ID倒序
      result.sort((a, b) => b.id - a.id);
    } else if (this.sortType === 2) {
      // 最热：按点赞数倒序
      result.sort((a, b) => (b.like_count || 0) - (a.like_count || 0));
    } else if (this.sortType === 3) {
      // 最多收藏：按收藏数倒序
      result.sort((a, b) => (b.fav_count || 0) - (a.fav_count || 0));
    }

    this.posts = result;
  }

  // 🎨 颜色滤镜工具：让首页的小心心也能变红
  getRedFilter() {
    return [
      0, 0, 0, 1, 0, // R = A
      0, 0, 0, 0, 0, // G = 0
      0, 0, 0, 0, 0, // B = 0
      0, 0, 0, 1, 0, // A = A
    ]
  }

  build() {
    Column() {
      Row() {
        TextInput({ placeholder: '搜标题/标签...', text: this.searchText })
          .layoutWeight(1).backgroundColor($r('app.color.input_bg')).borderRadius(18).height(36)
          .onChange(v => this.searchText = v).onSubmit(() => this.refreshList())
        Text("搜索").fontColor($r('app.color.text_primary')).margin({left: 10}).onClick(() => this.refreshList())
      }.padding({left: 10, right: 10, top: 5, bottom: 5})

      // 排序切换栏
      Row() {
        Text("推荐")
          .fontSize(14)
          .fontWeight(this.sortType === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.sortType === 0 ? $r('app.color.brand_red') : $r('app.color.text_secondary'))
          .onClick(() => {
            this.sortType = 0;
            this.refreshList();
          })

        Divider().vertical(true).height(12).margin({left: 15, right: 15}).color('#E0E0E0')

        Text("最新")
          .fontSize(14)
          .fontWeight(this.sortType === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.sortType === 1 ? $r('app.color.brand_red') : $r('app.color.text_secondary'))
          .onClick(() => {
            this.sortType = 1;
            this.refreshList();
          })
        
        Divider().vertical(true).height(12).margin({left: 15, right: 15}).color('#E0E0E0')
        
        Text("最热")
          .fontSize(14)
          .fontWeight(this.sortType === 2 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.sortType === 2 ? $r('app.color.brand_red') : $r('app.color.text_secondary'))
          .onClick(() => {
            this.sortType = 2;
            this.refreshList();
          })

        Divider().vertical(true).height(12).margin({left: 15, right: 15}).color('#E0E0E0')

        Text("最多收藏")
          .fontSize(14)
          .fontWeight(this.sortType === 3 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.sortType === 3 ? $r('app.color.brand_red') : $r('app.color.text_secondary'))
          .onClick(() => {
            this.sortType = 3;
            this.refreshList();
          })
      }
      .width('100%')
      .padding({left: 15, bottom: 10})
      .justifyContent(FlexAlign.Start)

      if (this.isLoading && this.posts.length === 0) {
        // 加载中提示
        Column() { Text("加载中...").fontColor($r('app.color.text_secondary')).margin({top: 50}) }.width('100%').height('100%')
      } else if (this.posts.length === 0) {
        // 空状态提示
        Column() {
          Text("暂无内容").fontColor($r('app.color.text_secondary')).margin({top: 50})
          Button("刷新").margin({top:10}).onClick(()=>this.loadData())
        }.width('100%').height('100%')
      } else {
        WaterFlow() {
          ForEach(this.posts, (item: ForumPost) => {
            FlowItem() {
              Column() {
                Image(item.images && item.images.length > 0 ? getImageUrl(item.images[0]) : '')
                  .width('100%').height(180).objectFit(ImageFit.Cover)
                  .borderRadius({topLeft: 8, topRight: 8}).backgroundColor('#E0E0E0')

                Text(item.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  .maxLines(2).textOverflow({overflow: TextOverflow.Ellipsis}).padding(8)

                Row() {
                  Row() {
                    Image(item.author_avatar ? `${DOMAIN}${item.author_avatar}` : '')
                      .width(16).height(16).borderRadius(8).backgroundColor('#ccc')
                    Text(item.author_name).fontSize(10).fontColor($r('app.color.text_secondary'))
                      .margin({left: 4}).layoutWeight(1).maxLines(1)
                  }.layoutWeight(1)

                  Row() {
                    // ⚡️ 首页点赞变色
                    SymbolGlyph(item.is_liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                      .fontSize(12)
                      .fontColor([item.is_liked ? Color.Red : $r('app.color.text_secondary')])
                    Text(` ${item.like_count}`).fontSize(10).fontColor($r('app.color.text_secondary'))

                    // ⚡️ 首页收藏变色
                    SymbolGlyph(item.is_faved ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                      .fontSize(12)
                      .fontColor([item.is_faved ? '#FFD700' : $r('app.color.text_secondary')])
                      .margin({left: 5})
                    Text(` ${item.fav_count || 0}`).fontSize(10).fontColor($r('app.color.text_secondary'))
                  }
                }.padding({left: 8, right: 8, bottom: 8}).width('100%').justifyContent(FlexAlign.SpaceBetween)
              }
              .backgroundColor($r('app.color.card_bg')).borderRadius(8)
              .onClick(() => {
                this.pageStack.pushPath({ name: 'PostDetail', param: new PostParams(item.id) })
              })
            }
          })
        }
        .columnsTemplate("1fr 1fr").columnsGap(10).rowsGap(10).padding(10)
        .layoutWeight(1).backgroundColor($r('app.color.page_bg'))
      }
    }
  }
}

// ===================== 帖子详情 (⚡️修复变色问题) =====================
@Component
struct PostDetailView {
  @StorageLink('currentUserId') currentUserId: number = 0;
  @Consume('pageStack') pageStack: NavPathStack;
  postId: number = 0;
  @State detail: PostDetailData | null = null;
  @State isLiked: boolean = false;
  @State isFaved: boolean = false;
  @State commentText: string = '';

  aboutToAppear() { this.loadDetail(); }

  async loadDetail() {
    const res = await ForumService.getPostDetail(this.postId);
    if (res.success && res.data) {
      this.detail = res.data;
      // ⚡️ 修复：防止 images/tags 是字符串
      if (typeof this.detail.post.images === 'string') {
         try { this.detail.post.images = JSON.parse(this.detail.post.images); } catch(e) { this.detail.post.images = []; }
      }
      if (typeof this.detail.post.tags === 'string') {
         try { this.detail.post.tags = JSON.parse(this.detail.post.tags); } catch(e) { this.detail.post.tags = []; }
      }
      this.isLiked = (this.detail.post.is_liked ?? 0) > 0;
      this.isFaved = (this.detail.post.is_faved ?? 0) > 0;
    }
  }

  async sendComment() {
    const uid = AppStorage.get<number>('currentUserId');
    if (!uid) { promptAction.showToast({message: '请先登录'}); return; }
    if (!this.commentText) return;
    await ForumService.sendComment(uid, this.postId, this.commentText);
    this.commentText = '';
    this.loadDetail();
  }

  async toggleLike() {
    const uid = AppStorage.get<number>('currentUserId');
    if (!uid) { promptAction.showToast({message: '请先登录'}); return; }
    
    // ⚡️ 乐观更新：立即更新UI
    this.isLiked = !this.isLiked;
    if (this.detail && this.detail.post) {
        this.detail.post.like_count = (this.detail.post.like_count || 0) + (this.isLiked ? 1 : -1);
        this.detail.post.is_liked = this.isLiked ? 1 : 0;
        
        // ⚡️ 实时同步：通知首页更新
        AppStorage.setOrCreate('postUpdate', { 
            id: this.postId, 
            like_count: this.detail.post.like_count, 
            is_liked: this.detail.post.is_liked,
            fav_count: this.detail.post.fav_count,
            is_faved: this.detail.post.is_faved
        });
    }

    await ForumService.likePost(this.postId, uid);
  }

  async toggleFav() {
    const uid = AppStorage.get<number>('currentUserId');
    if (!uid) { promptAction.showToast({message: '请先登录'}); return; }
    
    // ⚡️ 乐观更新：立即更新UI
    this.isFaved = !this.isFaved;
    if (this.detail && this.detail.post) {
        this.detail.post.fav_count = (this.detail.post.fav_count || 0) + (this.isFaved ? 1 : -1);
        this.detail.post.is_faved = this.isFaved ? 1 : 0;

        // ⚡️ 实时同步：通知首页更新
        AppStorage.setOrCreate('postUpdate', { 
            id: this.postId, 
            like_count: this.detail.post.like_count, 
            is_liked: this.detail.post.is_liked,
            fav_count: this.detail.post.fav_count,
            is_faved: this.detail.post.is_faved
        });
    }

    await ForumService.favPost(this.postId, uid);
  }

  async deletePost() {
    const uid = AppStorage.get<number>('currentUserId');
    if (!uid) return;
    
    const res = await promptAction.showDialog({
      title: '确认删除',
      message: '删除后无法恢复，确定要删除吗？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF0000' }
      ]
    });

    if (res.index === 1) {
      const result = await ForumService.deletePost(uid, this.postId);
      if (result.success) {
        promptAction.showToast({ message: '删除成功' });
        AppStorage.setOrCreate('refreshFeed', Date.now());
        this.pageStack.pop();
      } else {
        promptAction.showToast({ message: result.message || '删除失败' });
      }
    }
  }

  // 🔥 终极必杀技：颜色滤镜矩阵
  // 它可以强制把任何图片的像素变成你想要的颜色

  // 红色滤镜 (R=1, G=0, B=0)
  // 红色滤镜 (R=1, G=0, B=0)
  getRedFilter() {
    return [
      0, 0, 0, 1, 0, // R = A
      0, 0, 0, 0, 0, // G = 0
      0, 0, 0, 0, 0, // B = 0
      0, 0, 0, 1, 0, // A = A
    ]
  }

  // 黄色/金色滤镜 (R=1, G=0.8, B=0)
  getYellowFilter() {
    return [
      0, 0, 0, 1, 0, // R = A
      0, 0, 0, 0.8, 0, // G = 0.8 * A
      0, 0, 0, 0, 0, // B = 0
      0, 0, 0, 1, 0, // A = A
    ]
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([Color.Black])
            .onClick(() => this.pageStack.pop())
          
          Blank()
          
          // ✏️ 编辑按钮：只有作者自己可见
          if (this.detail && this.currentUserId === this.detail.post.user_id) {
            Row() {
              Text("编辑")
                .fontSize(16)
                .fontColor('#333')
                .onClick(() => {
                  const p = new PublishParams();
                  p.postId = this.detail?.post.id;
                  p.title = this.detail?.post.title;
                  p.content = this.detail?.post.content;
                  p.tags = this.detail?.post.tags ? this.detail?.post.tags.join(' ') : '';
                  p.images = this.detail?.post.images;
                  this.pageStack.pushPath({ name: 'PublishPage', param: p });
                })

              Text("删除")
                .fontSize(16)
                .fontColor(Color.Red)
                .margin({ left: 15 })
                .onClick(() => {
                  this.deletePost();
                })
            }
          }
        }.padding(10).width('100%')
        if (this.detail) {
          List() {
            ListItem() {
              Column() {
                Row() {
                  Image(this.detail.post.author_avatar ? `${DOMAIN}${this.detail.post.author_avatar}` : '')
                    .width(40).height(40).borderRadius(20).backgroundColor('#ccc')
                  Column() {
                    Text(this.detail.post.author_name).fontWeight(FontWeight.Bold)
                    Text('点击查看主页').fontSize(10).fontColor('#999')
                  }.margin({left: 10}).alignItems(HorizontalAlign.Start)
                }.padding(10).width('100%').onClick(() => {
                  this.pageStack.pushPath({ name: 'UserProfile', param: new PostParams(this.detail?.post.user_id ?? 0) })
                })

                if (this.detail.post.images && this.detail.post.images.length > 0) {
                  Swiper() {
                    ForEach(this.detail.post.images, (img: string) => {
                      Image(getImageUrl(img)).width('100%').objectFit(ImageFit.Contain)
                    })
                  }
                  .height(300)
                  .indicator(true)
                  .autoPlay(false)
                }

                Text(this.detail.post.title).fontSize(20).fontWeight(FontWeight.Bold).padding(10)
                Text(this.detail.post.content).fontSize(16).padding({left: 10, right: 10})
                
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.detail.post.tags, (tag: string) => {
                    Text('#' + tag)
                      .fontSize(14).fontColor('#007DFF')
                      .padding({ right: 10, top: 5, bottom: 5 })
                      .onClick(() => {
                        this.pageStack.pushPath({ name: 'SearchPage', param: new SearchParams(tag) })
                      })
                  })
                }.padding(10)
              }.alignItems(HorizontalAlign.Start)
            }
            ListItem() { Text(`评论 (${this.detail.comments.length})`).fontSize(14).fontColor('#999').padding(10).backgroundColor('#f5f5f5').width('100%') }
            ForEach(this.detail.comments, (c: Comment) => {
              ListItem() {
                Row() {
                  Image(c.avatar_url ? `${DOMAIN}${c.avatar_url}` : '').width(30).height(30).borderRadius(15).backgroundColor('#ccc')
                  Column() {
                    Text(c.nickname).fontSize(12).fontColor('#666')
                    Text(c.content).fontSize(14).margin({top: 2})
                  }.margin({left: 10}).alignItems(HorizontalAlign.Start)
                }.padding(10).width('100%')
              }
            })
          }.layoutWeight(1)

          Row() {
            TextInput({ placeholder: '说点什么...', text: this.commentText }).layoutWeight(1).backgroundColor('#F5F5F5').borderRadius(20).onChange(v => this.commentText = v).onSubmit(() => this.sendComment())
            Text("发送").fontColor('#007DFF').margin({left: 10}).onClick(() => this.sendComment())

            // ❤️ 点赞
            Row() {
              SymbolGlyph(this.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(24)
                .fontColor([this.isLiked ? Color.Red : '#999'])
              Text((this.detail?.post.like_count || 0).toString())
                .fontSize(12).fontColor('#666').margin({left: 4})
            }
            .margin({left: 15})
            .onClick(() => this.toggleLike())

            // 💛 收藏
            Row() {
              SymbolGlyph(this.isFaved ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                .fontSize(24)
                .fontColor([this.isFaved ? '#FFD700' : '#999'])
              Text((this.detail?.post.fav_count || 0).toString())
                .fontSize(12).fontColor('#666').margin({left: 4})
            }
            .margin({left: 15})
            .onClick(() => this.toggleFav())

          }.padding(10).border({width: {top: 1}, color: '#eee'})
        }
      }
    }.hideTitleBar(true)
  }
}

// ===================== 个人主页 =====================
@Component
struct ProfileView {
  @Consume('pageStack') pageStack: NavPathStack;
  userId: number = 0;
  isSelf: boolean = false;
  @State profile: ProfileData | null = null;
  @State currentTab: number = 0;
  @State errorMsg: string = '';

  @StorageProp('refreshFeed') @Watch('loadProfile') refreshSignal: number = 0;
  @StorageProp('postUpdate') @Watch('onPostUpdate') postUpdateSignal: Record<string, Object> = {};

  onPostUpdate() {
    const update = this.postUpdateSignal;
    if (!update || !update['id'] || !this.profile) return;

    const id = update['id'] as number;
    
    const updateList = (list: ForumPost[]) => {
      const index = list.findIndex(p => p.id === id);
      if (index !== -1) {
        list[index].like_count = update['like_count'] as number;
        list[index].is_liked = update['is_liked'] as number;
        list[index].fav_count = update['fav_count'] as number;
        list[index].is_faved = update['is_faved'] as number;
        return true;
      }
      return false;
    };

    let changed = false;
    if (updateList(this.profile.works)) changed = true;
    if (updateList(this.profile.likes)) changed = true;
    if (updateList(this.profile.favs)) changed = true;

    if (changed && this.profile) {
        // 强制刷新对象以触发UI更新
        this.profile = {
            info: this.profile.info,
            works: this.profile.works,
            likes: this.profile.likes,
            favs: this.profile.favs
        };
    }
  }

  dialogController: CustomDialogController | null = null;

  openEditDialog() {
    this.dialogController = new CustomDialogController({
      builder: EditProfileDialog({
        nickname: this.profile?.info.nickname || '',
        age: this.profile?.info.age || 0,
        weight: this.profile?.info.weight || 0,
        tags: this.profile?.info.health_tags || '',
        userId: this.userId,
        confirm: () => { this.loadProfile(); }
      }),
      autoCancel: true
    })
    this.dialogController.open()
  }

  // ⚡️ 修复：主动加载
  aboutToAppear() { this.loadProfile(); }
  onPageShow() { this.loadProfile(); }

  async loadProfile() {
    const res = await ForumService.getProfile(this.userId);
    if (res.success && res.data) {
      this.profile = res.data;
      // ⚡️ 修复：遍历作品、点赞、收藏列表，处理 images 字段
      const fixImages = (list: ForumPost[]) => {
        return list.map(item => {
          if (typeof item.images === 'string') {
            try { item.images = JSON.parse(item.images); } catch(e) { item.images = []; }
          }
          return item;
        });
      };
      this.profile.works = fixImages(this.profile.works);
      this.profile.likes = fixImages(this.profile.likes);
      this.profile.favs = fixImages(this.profile.favs);

      this.errorMsg = '';
    } else {
      this.errorMsg = res.message || '加载失败';
    }
  }

  build() {
    NavDestination() {
      Column() {
        if (this.errorMsg) {
          Text(this.errorMsg).margin({top:50}).fontColor(Color.Red).onClick(()=>this.loadProfile())
        } else if (this.profile) {
          Row() {
            if (!this.isSelf) Image($r('app.media.icon_back')).width(24).onClick(() => this.pageStack.pop())
            Blank()
            if (this.isSelf) {
              Button("退出").fontColor(Color.Red).backgroundColor(Color.Transparent).onClick(() => { AppStorage.setOrCreate('currentUserId', 0); })
            }
          }.width('100%').padding(10)

          Row() {
            Image(this.profile.info.avatar_url ? `${DOMAIN}${this.profile.info.avatar_url}` : '')
              .width(80).height(80).borderRadius(40).backgroundColor('#eee')
            Column() {
              Text(this.profile.info.nickname).fontSize(22).fontWeight(FontWeight.Bold)
              Text(`ID: ${this.profile.info.id}`).fontSize(12).fontColor('#999')
              Text(`标签: ${this.profile.info.health_tags || '无'}`).fontSize(12).fontColor('#FF2442').margin({top: 5})
            }.alignItems(HorizontalAlign.Start).margin({left: 20})
            Blank()
            if (this.isSelf) {
              Button("编辑资料").height(28).fontSize(12).backgroundColor('#eee').fontColor('#333').onClick(() => this.openEditDialog())
            }
          }.padding(20).width('100%')

          Row() {
            this.TabItem("作品", 0)
            this.TabItem("赞过", 1)
            this.TabItem("收藏", 2)
          }.width('100%').justifyContent(FlexAlign.SpaceAround).padding(10).border({width: {bottom: 1}, color: '#eee'})

          List() {
            ForEach(this.currentTab === 0 ? this.profile.works : (this.currentTab === 1 ? this.profile.likes : this.profile.favs), (item: ForumPost) => {
              ListItem() {
                Row() {
                  Image(item.images[0] ? getImageUrl(item.images[0]) : '').width(60).height(60).borderRadius(4).backgroundColor('#eee')
                  Column() {
                    Text(item.title).fontSize(16).maxLines(1)
                    Text(item.content).fontSize(12).fontColor('#999').maxLines(1).margin({top: 4})
                  }.margin({left: 10}).alignItems(HorizontalAlign.Start).layoutWeight(1)
                }.padding(10).width('100%').onClick(() => this.pageStack.pushPath({ name: 'PostDetail', param: new PostParams(item.id) }))
              }
            })
          }.layoutWeight(1)
        }
      }
    }.hideTitleBar(true)
  }
  @Builder TabItem(name: string, index: number) {
    Column() {
      Text(name).fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
      if (this.currentTab === index) Divider().width(20).strokeWidth(3).color('#FF2442').margin({top: 4})
    }.onClick(() => this.currentTab = index)
  }
}

// EditProfileDialog, PublishView, LoginView 保持不变 (引用上一版代码即可)
// ...
// 为了代码完整性，这里必须加上 EditProfileDialog, PublishView, LoginView
// 请直接复制上一版回答中的这三个组件的代码，因为它们逻辑是完全正确的。
@CustomDialog
struct EditProfileDialog {
  controller: CustomDialogController
  userId: number = 0
  @State nickname: string = ''
  @State age: number = 0
  @State weight: number = 0
  @State tags: string = ''
  confirm: () => void = () => {}

  async save() {
    // ⚡️ 修复：对参数进行 URL 编码，防止特殊字符导致解析失败
    // 同时发送 tags 和 health_tags 以兼容后端不同字段名
    const params = `user_id=${this.userId}` +
                   `&nickname=${encodeURIComponent(this.nickname)}` +
                   `&age=${this.age}` +
                   `&weight=${this.weight}` +
                   `&health_tags=${encodeURIComponent(this.tags)}` +
                   `&tags=${encodeURIComponent(this.tags)}`; // 双重保险
    
    console.info(`[EditProfile] Saving: ${params}`);
    const res = await ForumService.updateProfile(params);
    if (res.success) {
      promptAction.showToast({message: '保存成功'});
      this.confirm();
      this.controller.close();
    } else {
      promptAction.showToast({message: res.message || '保存失败'});
    }
  }

  async changeAvatar() {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({ MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
      if (result.photoUris.length > 0) {
        promptAction.showToast({message: '正在上传头像...'});
        const context = getContext(this) as common.UIAbilityContext;
        const file = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY);
        const name = `avatar_${Date.now()}.jpg`;
        const dest = `${context.cacheDir}/${name}`;
        fs.copyFileSync(file.fd, dest);
        fs.closeSync(file);
        const url = await ForumService.uploadImage(context, `internal://cache/${name}`);
        if (url) {
          await ForumService.updateProfile(`user_id=${this.userId}&avatar_url=${url}`);
          promptAction.showToast({message: '头像已更新'});
          this.confirm();
        }
      }
    } catch(e) {}
  }

  build() {
    Column({space: 15}) {
      Text("编辑资料").fontSize(18).fontWeight(FontWeight.Bold)
      Button("点击更换头像").fontSize(12).onClick(() => this.changeAvatar())
      TextInput({placeholder: '昵称', text: this.nickname}).onChange(v=>this.nickname=v)
      TextInput({placeholder: '年龄', text: this.age?.toString()}).type(InputType.Number).onChange(v=>this.age=parseInt(v))
      TextInput({placeholder: '体重', text: this.weight?.toString()}).type(InputType.Number).onChange(v=>this.weight=parseFloat(v))
      TextInput({placeholder: '推荐标签 (如: 减脂,瑜伽)', text: this.tags}).onChange(v=>this.tags=v)
      Row() {
        Button("取消").backgroundColor('#eee').fontColor('#333').onClick(() => this.controller.close())
        Blank().width(20)
        Button("保存").backgroundColor('#FF2442').onClick(() => this.save())
      }
    }.padding(20).backgroundColor(Color.White).borderRadius(10)
  }
}

@Component
struct PublishView {
  @Consume('pageStack') pageStack: NavPathStack;
  @State editPostId: number = 0; // 0表示新建，>0表示编辑
  @State title: string = '';
  @State content: string = '';
  @State tags: string = '';
  @State uploadedUrls: string[] = [];

  async selectImage() {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({ MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 9 });
      if (result.photoUris.length > 0) {
        this.doUploadBatch(result.photoUris);
      }
    } catch (e) {}
  }

  async doUploadBatch(uris: string[]) {
    promptAction.showToast({ message: '正在上传...' });
    const context = getContext(this) as common.UIAbilityContext;
    let successCount = 0;
    
    for (const srcUri of uris) {
        try {
          const file = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
          const name = `pub_${Date.now()}_${Math.random().toString().slice(2,8)}.jpg`;
          const dest = `${context.cacheDir}/${name}`;
          try { fs.unlinkSync(dest); } catch(e) {}
          fs.copyFileSync(file.fd, dest);
          fs.closeSync(file);
          const url = await ForumService.uploadImage(context, `internal://cache/${name}`);
          if (url) {
            this.uploadedUrls.push(url);
            successCount++;
          }
        } catch(e) { console.error("Upload failed", e); }
    }
    
    if (successCount > 0) {
        promptAction.showToast({message:`成功上传 ${successCount} 张图片`});
    } else {
        promptAction.showToast({message:'上传失败'});
    }
  }

  async doPublish() {
    const uid = AppStorage.get<number>('currentUserId');
    // Convert tags string to array string
    const tagArray = this.tags.split(/[,，\s]+/).filter(t => t.trim() !== '');
    const finalTags = JSON.stringify(tagArray);
    
    const finalImg = JSON.stringify(this.uploadedUrls);
    
    let res: ApiResponse<null>;
    if (this.editPostId > 0) {
      // 编辑模式
      const params = `post_id=${this.editPostId}&user_id=${uid}&title=${this.title}&content=${this.content}&tags=${finalTags}&images=${finalImg}`;
      res = await ForumService.updatePost(params);
    } else {
      // 发布模式
      const params = `user_id=${uid}&title=${this.title}&content=${this.content}&tags=${finalTags}&images=${finalImg}`;
      res = await ForumService.publish(params);
    }

    if (res.success) {
      promptAction.showToast({message: this.editPostId > 0 ? '修改成功!' : '发布成功!'});
      AppStorage.setOrCreate('refreshFeed', Date.now()); // 触发刷新
      this.pageStack.pop();
    } else {
      promptAction.showToast({message: res.message || (this.editPostId > 0 ? '修改失败' : '发布失败')});
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text("取消").onClick(() => this.pageStack.pop()).fontSize(16).fontColor($r('app.color.text_primary'))
          Blank()
          Button(this.editPostId > 0 ? "保存" : "发布").height(32).backgroundColor($r('app.color.brand_red')).fontSize(14).onClick(() => this.doPublish())
        }.padding(15).width('100%')
        TextInput({ placeholder: '标题', text: this.title })
          .fontSize(18).fontWeight(FontWeight.Bold).margin(10)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.input_bg'))
          .onChange(v=>this.title=v)
        TextArea({ placeholder: '正文...', text: this.content })
          .height(100).margin(10)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .onChange(v=>this.content=v)
        TextInput({ placeholder: '#标签 (用空格分隔)', text: this.tags })
          .margin({top: 10, left: 10, right: 10})
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.input_bg'))
          .onChange(v=>this.tags=v)
        Text("提示：tag会自动加上#").fontSize(12).fontColor($r('app.color.text_secondary')).margin({left: 15, bottom: 10})
        
        // Image Grid
        Grid() {
            ForEach(this.uploadedUrls, (img: string, index: number) => {
                GridItem() {
                    Stack({ alignContent: Alignment.TopEnd }) {
                        Image(getImageUrl(img)).width('100%').height(100).borderRadius(8).objectFit(ImageFit.Cover)
                        // Delete button
                        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                            .fontSize(24)
                            .fontColor([Color.Red])
                            .backgroundColor($r('app.color.bg_card'))
                            .borderRadius(12)
                            .margin(5)
                            .zIndex(1)
                            .onClick(() => {
                                // Create a new array to ensure UI update
                                let newUrls = [...this.uploadedUrls];
                                newUrls.splice(index, 1);
                                this.uploadedUrls = newUrls;
                            })
                    }
                }
            })
            GridItem() {
                Column() {
                    Image($r('app.media.ic_public_add')).width(30).height(30).fillColor($r('app.color.text_secondary'))
                    Text("添加图片").fontSize(12).fontColor($r('app.color.text_secondary')).margin({top:5})
                }
                .width('100%').height(100).backgroundColor('#F5F5F5').borderRadius(8)
                .justifyContent(FlexAlign.Center)
                .onClick(() => this.selectImage())
            }
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .padding(10)
        .height(300)

      }
    }.hideTitleBar(true)
  }
}

@Component
struct LoginView {
  @State username: string = '';
  @State password: string = '';
  async doLogin() {
    const params = `username=${this.username}&password=${this.password}`;
    const res = await ForumService.login(params);
    if (res.success && res.data) {
      AppStorage.setOrCreate('currentUserId', res.data.id);
      promptAction.showToast({message: `欢迎 ${res.data.nickname}`});
    } else {
      promptAction.showToast({message: res.message || '登录失败'});
    }
  }
  build() {
    Column({ space: 15 }) {
      Image($r('app.media.app_icon')).width(80).height(80).borderRadius(15).margin({top: 50})
      TextInput({ placeholder: '用户名', text: this.username })
        .width('50%')
        .backgroundColor($r('app.color.input_bg'))
        .fontColor($r('app.color.text_primary'))
        .onChange(v=>this.username=v)
      TextInput({ placeholder: '密码', text: this.password })
        .type(InputType.Password)
        .width('50%')
        .backgroundColor($r('app.color.input_bg'))
        .fontColor($r('app.color.text_primary'))
        .onChange(v=>this.password=v)
      Button("登录 / 注册").width('35%').height(45).backgroundColor($r('app.color.brand_red')).margin({top: 20}).onClick(() => this.doLogin())
    }.width('100%').height('100%').backgroundColor($r('app.color.page_bg'))
  }
}

@Component
struct SearchPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State keyword: string = '';
  @State searchResults: ForumPost[] = [];
  @State isLoading: boolean = false;

  // ⚡️ 修复：监听全局刷新信号，实现数据实时同步
  @StorageProp('refreshFeed') @Watch('doSearch') refreshSignal: number = 0;
  @StorageProp('postUpdate') @Watch('onPostUpdate') postUpdateSignal: Record<string, Object> = {};
  // ⚡️ 修复：监听用户登录状态变化
  @StorageLink('currentUserId') @Watch('doSearch') currentUserId: number = 0;

  onPostUpdate() {
    const update = this.postUpdateSignal;
    if (!update || !update['id']) return;

    const id = update['id'] as number;
    const index = this.searchResults.findIndex(p => p.id === id);
    if (index !== -1) {
      this.searchResults[index].like_count = update['like_count'] as number;
      this.searchResults[index].is_liked = update['is_liked'] as number;
      this.searchResults[index].fav_count = update['fav_count'] as number;
      this.searchResults[index].is_faved = update['is_faved'] as number;
      this.searchResults = [...this.searchResults];
    }
  }

  aboutToAppear() {
    if (this.keyword) {
      this.doSearch();
    }
  }

  async doSearch() {
    this.isLoading = true;
    // ⚡️ 修复：使用前端过滤，确保Tag搜索生效 (与首页逻辑保持一致)
    // 1. 获取所有数据 (传空字符串)
    const res = await ForumService.getFeed("");
    if (res.success && res.data) {
      // 2. 数据清洗
      let allPosts = res.data.map(item => {
        if (typeof item.images === 'string') {
            try { item.images = JSON.parse(item.images); } catch(e) { item.images = []; }
        }
        if (typeof item.tags === 'string') {
            try { item.tags = JSON.parse(item.tags); } catch(e) { item.tags = []; }
        }
        return item;
      });

      // 3. 前端过滤
      if (this.keyword && this.keyword.trim().length > 0) {
        const k = this.keyword.toLowerCase().trim();
        this.searchResults = allPosts.filter(post => {
          const matchTitle = post.title && post.title.toLowerCase().includes(k);
          const matchContent = post.content && post.content.toLowerCase().includes(k);
          const matchTags = post.tags && Array.isArray(post.tags) && post.tags.some(tag => tag.toLowerCase().includes(k));
          return matchTitle || matchContent || matchTags;
        });
      } else {
        this.searchResults = allPosts;
      }
    } else {
      this.searchResults = [];
    }
    this.isLoading = false;
  }

  build() {
    NavDestination() {
      Column() {
        // Search Bar
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .margin({right: 10})
            .onClick(() => this.pageStack.pop())
          TextInput({ placeholder: '搜索...', text: this.keyword })
            .layoutWeight(1)
            .height(40)
            .onChange((value) => {
              this.keyword = value;
            })
            .onSubmit(() => {
              this.doSearch();
            })
          Button("搜索")
            .margin({left: 10})
            .height(30)
            .fontSize(14)
            .onClick(() => this.doSearch())
        }.padding(10).width('100%').backgroundColor($r('app.color.page_bg'))

        if (this.isLoading) {
          LoadingProgress().width(50).height(50).margin({top: 50})
        } else if (this.searchResults.length === 0) {
          Text("暂无相关内容").margin({top: 50}).fontColor($r('app.color.text_secondary'))
        } else {
          List({ space: 10 }) {
            ForEach(this.searchResults, (item: ForumPost) => {
              ListItem() {
                Row() {
                  Image(getImageUrl(item.images && item.images.length > 0 ? item.images[0] : ''))
                    .width(100).height(100).borderRadius(8).objectFit(ImageFit.Cover).backgroundColor($r('app.color.input_bg'))
                  Column() {
                    Text(item.title).fontSize(16).fontWeight(FontWeight.Bold).maxLines(1).textOverflow({overflow: TextOverflow.Ellipsis}).fontColor($r('app.color.text_primary'))
                    Text(item.content).fontSize(14).fontColor($r('app.color.text_secondary')).maxLines(2).textOverflow({overflow: TextOverflow.Ellipsis}).margin({top: 5})
                    Row() {
                      Image(item.author_avatar ? `${DOMAIN}${item.author_avatar}` : $r('app.media.app_icon'))
                        .width(20).height(20).borderRadius(10)
                      Text(item.author_name).fontSize(12).fontColor($r('app.color.text_secondary')).margin({left: 5})
                      SymbolGlyph(item.is_liked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                        .fontSize(14)
                        .fontColor([item.is_liked ? Color.Red : $r('app.color.text_secondary')])
                      Text(item.like_count.toString()).fontSize(12).fontColor($r('app.color.text_secondary')).margin({left: 2})

                      Blank()

                      SymbolGlyph(item.is_faved ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                        .fontSize(14)
                        .fontColor([item.is_faved ? '#FFD700' : $r('app.color.text_secondary')])
                      Text((item.fav_count || 0).toString()).fontSize(12).fontColor($r('app.color.text_secondary')).margin({left: 2})
                    }.width('100%').margin({top: 10})
                  }.layoutWeight(1).height(100).padding({left: 10}).justifyContent(FlexAlign.SpaceBetween).alignItems(HorizontalAlign.Start)
                }
                .width('100%').padding(10).backgroundColor(Color.White).borderRadius(8)
                .onClick(() => {
                  this.pageStack.pushPath({ name: 'PostDetail', param: new PostParams(item.id) });
                })
              }
            })
          }.layoutWeight(1).width('100%').padding(10)
        }
      }.height('100%').backgroundColor('#F5F5F5')
    }.hideTitleBar(true)
  }
}