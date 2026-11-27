const api = require('../../utils/api')
const dishImages = require('../../utils/dish-images')
const dishTags = require('../../utils/dish-tags')
const cart = require('../../utils/cart')
const recent = require('../../utils/recent')

Page({
  data: {
    kitchenId: 0,
    kitchen: null,
    isMember: false,
    loading: true,
    error: '',
    missing: false,
    categories: [],
    activeCategoryId: 0,
    dishes: [],
    shownDishes: [],
    cartCount: 0,
    blockedCount: 0,
    allTags: [],
    pickedTags: [],
  },

  onLoad(options) {
    this.kitchenId = Number((options && options.kitchenId) || 0)
    this.setData({ kitchenId: this.kitchenId })
    if (!this.kitchenId) {
      this.setData({ loading: false, error: '没有指定厨房，请从首页选一个厨房', missing: true })
      return
    }
    // 记下这是最近去过的厨房：顾客首页会把它显示成「继续点菜」，搜索页也拿它当默认范围
    recent.writeLastKitchen(this.kitchenId)
    this.load()
  },

  onShow() {
    if (!this.kitchenId) return
    this.setData({ cartCount: cart.totalCount(cart.readCart(this.kitchenId)) })
    if (this.loadedOnce) this.load()
  },

  onPullDownRefresh() {
    this.load().then(function () {
      wx.stopPullDownRefresh()
    })
  },

  onShareAppMessage() {
    const kitchen = this.data.kitchen
    return {
      title: kitchen ? '看看「' + kitchen.name + '」今天有什么菜' : '看看我家今天的菜单',
      path: '/pages/menu/menu?kitchenId=' + this.kitchenId,
    }
  },

  load() {
    const that = this
    const id = this.kitchenId
    this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function (user) {
        return Promise.all([
          api.fetchKitchen(id),
          api.fetchCategories({ kitchenId: id, publicOnly: true }),
          api.fetchDishes({ kitchenId: id, publicOnly: true }),
          api.fetchIngredients({ kitchenId: id }),
          api.fetchRecipes({ kitchenId: id }),
          api.fetchMembers(id).catch(function () {
            return []
          }),
          // 标签条只是辅助筛选，拿不到就不显示，不该拖垮整页
          api.listKitchenTags(id).catch(function () {
            return []
          }),
        ]).then(function (result) {
          return { user: user, result: result }
        })
      })
      .then(function (payload) {
        const kitchen = payload.result[0]
        if (!kitchen) {
          that.missingKitchen = true
          throw new Error('这个厨房不存在，或者你还看不到它')
        }
        const categories = payload.result[1] || []
        const dishes = payload.result[2] || []
        const ingredients = payload.result[3] || []
        const recipes = payload.result[4] || []
        const members = payload.result[5] || []
        const availability = api.buildAvailability(dishes, ingredients, recipes)
        return api
          .signImageUrls(
            dishes.map(function (dish) {
              return dishImages.paths(dish)[0]
            })
          )
          .then(function (urls) {
            return {
              kitchen: kitchen,
              categories: categories,
              dishes: dishes,
              urls: urls,
              tags: payload.result[6] || [],
              availability: availability,
              isMember: members.some(function (row) {
                return row.user_id === payload.user.id
              }),
            }
          })
      })
      .then(function (payload) {
        let blocked = 0
        const prepared = payload.dishes.map(function (dish) {
          const info = payload.availability[dish.id] || { hasRecipe: false, canMake: null, lacks: [] }
          const soldOut = info.canMake !== null && info.canMake <= 0
          if (soldOut) blocked += 1
          return Object.assign({}, dish, {
            initial: String(dish.name || '菜').slice(0, 1),
            imageUrl: payload.urls[dishImages.paths(dish)[0]] || '',
            soldOut: soldOut,
            canMake: info.canMake,
            canMakeText: info.canMake && info.canMake > 0 ? '还能做 ' + info.canMake + ' 份' : '',
            lacks: info.lacks || [],
            tagList: dishTags.tags(dish),
          })
        })
        that.loadedOnce = true
        that.setData(
          {
            kitchen: payload.kitchen,
            isMember: payload.isMember,
            categories: payload.categories,
            dishes: prepared,
            loading: false,
            blockedCount: blocked,
            allTags: that.decorateTags(payload.tags || [], that.data.pickedTags),
          },
          function () {
            that.applyFilter()
          }
        )
        wx.setNavigationBarTitle({ title: payload.kitchen.name || '今日菜单' })
      })
      .catch(function (err) {
        const missing = !!that.missingKitchen
        // 自动跳到「上次的厨房」时，那个厨房可能已经被删掉、或者你已经不在里面了，
        // 把这笔记忆清掉，免得每次打开小程序都撞在同一个墙上。
        if (missing) recent.forgetIf(that.kitchenId)
        that.setData({ loading: false, error: api.friendly(err), missing: missing })
      })
  },

  // ---------- 标签 ----------

  decorateTags(rows, picked) {
    const chosen = dishTags.clean(picked)
    return api.asArray(rows).map(function (item) {
      return Object.assign({}, item, { picked: chosen.indexOf(item.name) >= 0 })
    })
  },

  pickTag(event) {
    const name = event.currentTarget.dataset.name
    const picked = dishTags.clean(this.data.pickedTags)
    const at = picked.indexOf(name)
    if (at >= 0) picked.splice(at, 1)
    else picked.push(name)
    this.setData({ pickedTags: picked, allTags: this.decorateTags(this.data.allTags, picked) })
    this.applyFilter()
  },

  clearTags() {
    this.setData({ pickedTags: [], allTags: this.decorateTags(this.data.allTags, []) })
    this.applyFilter()
  },

  applyFilter() {
    const state = this.data
    // 标签是「同时满足」：选了「辣」和「素」，就只出两者都有的菜
    const picked = dishTags.clean(state.pickedTags)
    const shown = state.dishes.filter(function (dish) {
      if (state.activeCategoryId !== 0 && dish.category_id !== state.activeCategoryId) return false
      if (!picked.length) return true
      const own = dishTags.tags(dish)
      return picked.every(function (name) {
        return own.indexOf(name) >= 0
      })
    })
    this.setData({ shownDishes: shown })
  },

  pickCategory(event) {
    const id = Number(event.currentTarget.dataset.id) || 0
    const that = this
    this.setData({ activeCategoryId: id }, function () {
      that.applyFilter()
    })
  },

  findDish(id) {
    return this.data.dishes.filter(function (item) {
      return item.id === id
    })[0]
  },

  addToCart(event) {
    const id = Number(event.currentTarget.dataset.id)
    const dish = this.findDish(id)
    if (!dish) return
    if (dish.soldOut) {
      this.explainShortage(dish)
      return
    }
    const current = cart.readCart(this.kitchenId)
    const entry = current[id] || { id: id, name: dish.name, count: 0 }
    const limit = dish.canMake
    if (limit !== null && limit !== undefined && entry.count + 1 > limit) {
      wx.showToast({ title: '食材只够做 ' + limit + ' 份', icon: 'none' })
      return
    }
    entry.name = dish.name
    entry.kitchen_id = dish.kitchen_id
    entry.count = entry.count + 1
    current[id] = entry
    cart.writeCart(this.kitchenId, current)
    this.setData({ cartCount: cart.totalCount(current) })
  },

  // 食材不够时：说清楚缺什么，并留一条提醒给这个厨房的管理者。
  explainShortage(dish) {
    const lacks = dish.lacks || []
    const lines = lacks.map(function (item) {
      return (
        '· ' +
        item.ingredientName +
        '：一份要用 ' +
        api.round1(item.amount) +
        item.unit +
        '，现在只剩 ' +
        api.round1(item.stock) +
        item.unit
      )
    })
    wx.showModal({
      title: '「' + dish.name + '」现在做不了',
      content: (lines.join('\n') || '食材不够了') + '\n\n已经把缺料告诉这个厨房的管理者了。',
      showCancel: false,
      confirmText: '知道了',
    })
    api
      .reportShortage({
        kitchenId: dish.kitchen_id || this.kitchenId,
        dinerName: cart.readDinerName(),
        dishName: dish.name,
        problems: lacks.map(function (item) {
          return {
            ingredientName: item.ingredientName,
            needed: item.amount,
            stock: item.stock,
            dishes: dish.name,
          }
        }),
      })
      .catch(function () {
        // 提醒只是锦上添花，失败不打扰点菜的人
      })
  },

  // 点「暂无」的菜时也能问清楚缺什么
  explainShortageById(event) {
    const dish = this.findDish(Number(event.currentTarget.dataset.id))
    if (dish) this.explainShortage(dish)
  },

  openDish(event) {
    const id = Number(event.currentTarget.dataset.id)
    wx.navigateTo({ url: '/pages/dish/dish?id=' + id + '&kitchenId=' + this.kitchenId })
  },

  goCart() {
    wx.navigateTo({ url: '/pages/cart/cart?kitchenId=' + this.kitchenId })
  },

  goSearch() {
    wx.navigateTo({ url: '/pages/search/search?kitchenId=' + this.kitchenId })
  },

  goOrders() {
    // 订单页是 tab 页，只能 switchTab；成员落到「我收到的」，顾客落到「我点的」
    const app = getApp()
    if (app && app.globalData) app.globalData.ordersSegment = this.data.isMember ? 'received' : 'mine'
    wx.switchTab({ url: '/pages/orders/orders' })
  },

  goManage() {
    wx.navigateTo({ url: '/pages/manage/manage?kitchenId=' + this.kitchenId })
  },

  goHome() {
    // 是自己的厨房就回「下厨」看厨房列表，只是来点菜的顾客就回「点菜」看别家
    wx.switchTab({ url: this.data.isMember ? '/pages/chef/chef' : '/pages/home/home' })
  },
})
