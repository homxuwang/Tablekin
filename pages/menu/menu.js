const api = require('../../utils/api')
const dishImages = require('../../utils/dish-images')
const dishTags = require('../../utils/dish-tags')
const cart = require('../../utils/cart')
const recent = require('../../utils/recent')
const haptics = require('../../utils/haptics')

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
    cartItems: [],
    showCartSheet: false,
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
    this.syncCartState()
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

  // 把本地购物车的每道菜数量同步到菜品卡片、分类角标与底部抽屉
  syncCartState(sourceCart) {
    const current = sourceCart || cart.readCart(this.kitchenId)
    const total = cart.totalCount(current)
    const items = cart.toList(current)
    const qtyByDish = {}
    items.forEach(function (entry) {
      qtyByDish[entry.id] = entry.count
    })
    const dishes = (this.data.dishes || []).map(function (dish) {
      return Object.assign({}, dish, { cartQty: qtyByDish[dish.id] || 0 })
    })
    const cartByCat = {}
    const countByCat = {}
    dishes.forEach(function (dish) {
      const cid = dish.category_id || 0
      countByCat[cid] = (countByCat[cid] || 0) + 1
      if (dish.cartQty > 0) {
        cartByCat[cid] = (cartByCat[cid] || 0) + dish.cartQty
      }
    })
    const categories = (this.data.categories || []).map(function (cat) {
      return Object.assign({}, cat, {
        dishCount: countByCat[cat.id] || 0,
        cartQty: cartByCat[cat.id] || 0,
      })
    })
    const patch = {
      cartCount: total,
      cartItems: items,
      dishes: dishes,
      categories: categories,
    }
    if (total === 0 && this.data.showCartSheet) {
      patch.showCartSheet = false
    }
    const that = this
    this.setData(patch, function () {
      that.applyFilter()
    })
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
        const currentCart = cart.readCart(id)
        let blocked = 0
        const prepared = payload.dishes.map(function (dish) {
          const info = payload.availability[dish.id] || { hasRecipe: false, canMake: null, lacks: [] }
          const soldOut = info.canMake !== null && info.canMake <= 0
          const unavailable = dish.is_available === false
          if (soldOut) blocked += 1
          const cartEntry = currentCart[dish.id]
          return Object.assign({}, dish, {
            initial: String(dish.name || '菜').slice(0, 1),
            imageUrl: payload.urls[dishImages.paths(dish)[0]] || '',
            soldOut: soldOut,
            unavailable: unavailable,
            canMake: info.canMake,
            canMakeText: info.canMake && info.canMake > 0 ? '还能做 ' + info.canMake + ' 份' : '',
            lacks: info.lacks || [],
            tagList: dishTags.tags(dish),
            cartQty: cartEntry && cartEntry.count > 0 ? cartEntry.count : 0,
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
            that.syncCartState(currentCart)
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
    haptics.light()
    const name = event.currentTarget.dataset.name
    const picked = dishTags.clean(this.data.pickedTags)
    const at = picked.indexOf(name)
    if (at >= 0) picked.splice(at, 1)
    else picked.push(name)
    this.setData({ pickedTags: picked, allTags: this.decorateTags(this.data.allTags, picked) })
    this.applyFilter()
  },

  clearTags() {
    haptics.light()
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
    haptics.light()
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

  addDishById(id) {
    const dish = this.findDish(id)
    if (!dish) return false
    if (dish.unavailable || dish.is_available === false) {
      wx.showToast({ title: '「' + dish.name + '」已下架，暂时点不了', icon: 'none' })
      return false
    }
    if (dish.soldOut) {
      this.explainShortage(dish)
      return false
    }
    const current = cart.readCart(this.kitchenId)
    const entry = current[id] || { id: id, name: dish.name, count: 0 }
    const limit = dish.canMake
    if (limit !== null && limit !== undefined && entry.count + 1 > limit) {
      wx.showToast({ title: '食材只够做 ' + limit + ' 份', icon: 'none' })
      return false
    }
    entry.name = dish.name
    entry.kitchen_id = dish.kitchen_id
    entry.count = entry.count + 1
    current[id] = entry
    cart.writeCart(this.kitchenId, current)
    haptics.light()
    this.syncCartState(current)
    return true
  },

  addToCart(event) {
    this.addDishById(Number(event.currentTarget.dataset.id))
  },

  decreaseFromCart(event) {
    const id = Number(event.currentTarget.dataset.id)
    const current = cart.readCart(this.kitchenId)
    const entry = current[id]
    if (!entry) return
    if (entry.count <= 1) delete current[id]
    else entry.count = entry.count - 1
    cart.writeCart(this.kitchenId, current)
    haptics.light()
    this.syncCartState(current)
  },

  explainUnavailable(event) {
    const dish = this.findDish(Number(event.currentTarget.dataset.id))
    wx.showToast({
      title: dish ? '「' + dish.name + '」今天暂不上架' : '这道菜已下架',
      icon: 'none',
    })
  },

  // 「今天吃啥」随机推荐：从可点菜品中随机挑一道，解决选择困难
  pickRandomDish() {
    const pool = (this.data.shownDishes.length ? this.data.shownDishes : this.data.dishes).filter(
      function (dish) {
        return !dish.soldOut && !dish.unavailable && dish.is_available !== false
      }
    )
    if (!pool.length) {
      wx.showToast({ title: '当前没有可点的菜品', icon: 'none' })
      return
    }
    haptics.light()
    const chosen = pool[Math.floor(Math.random() * pool.length)]
    const that = this
    wx.showModal({
      title: '今天试试「' + chosen.name + '」？',
      content: chosen.description || '大厨拿手菜，点击即可加入点菜清单。',
      confirmText: '就点这道',
      cancelText: pool.length > 1 ? '换一道' : '再想想',
      success(res) {
        if (res.confirm) {
          if (that.addDishById(chosen.id)) {
            wx.showToast({ title: '已加入「' + chosen.name + '」', icon: 'success' })
          }
        } else if (res.cancel && pool.length > 1) {
          that.pickRandomDish()
        }
      },
    })
  },

  // 底部点菜抽屉：不离开菜单页就能查看、增减或清空已选菜品
  toggleCartSheet() {
    if (!this.data.cartCount) return
    haptics.light()
    this.setData({ showCartSheet: !this.data.showCartSheet })
  },

  closeCartSheet() {
    this.setData({ showCartSheet: false })
  },

  noop() {},

  clearCartFromMenu() {
    const that = this
    wx.showModal({
      title: '清空已选菜品？',
      content: '清空后可以重新挑选。',
      confirmColor: '#C93A3A',
      success(res) {
        if (!res.confirm) return
        cart.clear(that.kitchenId)
        that.syncCartState({})
      },
    })
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
    this.setData({ showCartSheet: false })
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
