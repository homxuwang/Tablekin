const api = require('../../utils/api')
const cart = require('../../utils/cart')
const meal = require('../../utils/meal-time')
const defaultEndTime = meal.defaultEndTime

// 结算页：确认点菜清单、说清什么时候吃、写清备注，然后发给大厨。
Page({
  data: {
    kitchenId: 0,
    kitchenName: '',
    items: [],
    total: 0,
    note: '',
    summary: '',
    dinerName: '',
    submitting: false,
    checking: false,
    shortage: null,
    orderDate: '',
    today: '',
    maxDate: '',
    mealType: 'point',
    timeStart: '18:30',
    timeEnd: '19:30',
    quickTimes: ['12:00', '17:30', '18:00', '18:30'],
    timeHint: '',
    mealText: '',
  },

  onLoad(options) {
    this.kitchenId = Number((options && options.kitchenId) || 0)
    const schedule = meal.defaultSchedule()
    this.setData({
      kitchenId: this.kitchenId,
      orderDate: schedule.orderDate,
      today: api.todayString(),
      maxDate: meal.maxOrderDate(),
      timeStart: schedule.timeStart,
      timeEnd: schedule.timeEnd,
    })
    this.updateTimeHint()
  },

  onShow() {
    this.setData({ today: api.todayString(), maxDate: meal.maxOrderDate() })
    this.stockPromise = null
    this.setData({ dinerName: cart.readDinerName() })
    this.refresh()
    this.checkStock()
    this.loadKitchenName()
  },

  loadKitchenName() {
    const that = this
    if (!this.kitchenId) return
    api
      .fetchKitchen(this.kitchenId)
      .then(function (kitchen) {
        const name = kitchen ? kitchen.name : ''
        that.setData({ kitchenName: name })
        if (name) wx.setNavigationBarTitle({ title: name + ' · 确认点菜' })
      })
      .catch(function () {
        // 名字取不到不影响点菜
      })
  },

  refresh() {
    const that = this
    const list = cart.toList(cart.readCart(this.kitchenId))
    const total = list.reduce(function (sum, item) {
      return sum + item.count
    }, 0)
    this.setData({ items: list, total: total }, function () {
      that.buildSummary()
    })
  },

  buildSummary() {
    const name = String(this.data.dinerName || '').trim()
    const kitchen = String(this.data.kitchenName || '').trim()
    const head = name ? name + ' 的点菜' : '今日点菜'
    const lines = [
      (kitchen ? '给「' + kitchen + '」：' : '') + head + '（共 ' + this.data.total + ' 份）',
      '想吃时间：' + this.mealTimeText(),
      '',
    ]
    this.data.items.forEach(function (item, index) {
      lines.push(index + 1 + '. ' + item.name + ' ×' + item.count)
    })
    const note = String(this.data.note || '').trim()
    if (note) {
      lines.push('')
      lines.push('备注：' + note)
    }
    this.setData({ summary: lines.join('\n') })
  },

  // ---------- 就餐时间 ----------

  mealTimeText() {
    const type = this.data.mealType
    const date = this.data.orderDate ? this.data.orderDate + ' · ' : ''
    if (type === 'asap') return date + '尽快'
    if (type === 'range') {
      return date + (this.data.timeEnd
        ? this.data.timeStart + '–' + this.data.timeEnd
        : this.data.timeStart + ' 之后')
    }
    return date + this.data.timeStart
  },

  updateTimeHint() {
    const that = this
    const type = this.data.mealType
    let hint = ''
    if (type === 'asap') hint = '做好就吃，大厨看着安排'
    else if (type === 'range') {
      hint = this.data.timeEnd
        ? '这个时间段里吃上就行'
        : this.data.timeStart + ' 之后什么时候都好'
    } else hint = '希望 ' + this.data.timeStart + ' 能吃上'
    this.setData({ timeHint: hint, mealText: this.mealTimeText() }, function () {
      that.buildSummary()
    })
  },

  pickAsap() {
    if (this.data.orderDate !== api.todayString()) {
      wx.showToast({ title: '尽快仅适用于今天', icon: 'none' })
      return
    }
    this.setData({ mealType: 'asap' }, this.updateTimeHint)
  },

  onMealDate(event) {
    const date = String(event.detail.value || '')
    const patch = { orderDate: date }
    if (date !== api.todayString() && this.data.mealType === 'asap') patch.mealType = 'point'
    this.setData(patch, this.updateTimeHint)
  },

  pickPoint() {
    this.setData({ mealType: 'point' }, this.updateTimeHint)
  },

  pickRange() {
    if (!this.data.timeEnd) {
      this.setData({ timeEnd: defaultEndTime(this.data.timeStart) })
    }
    this.setData({ mealType: 'range' }, this.updateTimeHint)
  },

  pickQuick(event) {
    const time = String(event.currentTarget.dataset.time || '')
    if (!time) return
    this.setData({ timeStart: time, timeEnd: defaultEndTime(time) }, this.updateTimeHint)
  },

  onTimeStart(event) {
    const start = String(event.detail.value || '')
    const patch = { timeStart: start }
    // 区间结束时间跟着开始时间走，避免出现「18:00 到 12:00」这种
    if (this.data.mealType === 'range' && (!this.data.timeEnd || this.data.timeEnd <= start)) {
      patch.timeEnd = defaultEndTime(start)
    }
    this.setData(patch, this.updateTimeHint)
  },

  onTimeEnd(event) {
    this.setData({ timeEnd: String(event.detail.value || '') }, this.updateTimeHint)
  },

  clearEnd() {
    this.setData({ timeEnd: '' }, this.updateTimeHint)
  },

  // ---------- 食材核对 ----------

  ensureStockData() {
    const that = this
    if (this.stockPromise) return this.stockPromise
    const id = this.kitchenId
    this.stockPromise = Promise.all([
      api.fetchDishes({ kitchenId: id, publicOnly: true }),
      api.fetchIngredients({ kitchenId: id }),
      api.fetchRecipes({ kitchenId: id }),
    ])
      .then(function (result) {
        that.stockData = {
          dishes: result[0] || [],
          ingredients: result[1] || [],
          recipes: result[2] || [],
        }
        return that.stockData
      })
      .catch(function () {
        that.stockPromise = null
        return null
      })
    return this.stockPromise
  },

  checkStock() {
    const that = this
    const list = cart.toList(cart.readCart(this.kitchenId))
    if (!list.length) {
      this.setData({ shortage: null, checking: false })
      return Promise.resolve()
    }
    this.setData({ checking: true })
    return this.ensureStockData().then(function (data) {
      if (!data) {
        that.setData({ checking: false })
        return
      }
      const wanted = {}
      list.forEach(function (item) {
        wanted[item.id] = item.count
      })
      const check = api.checkOrderAvailability(data.dishes, data.ingredients, data.recipes, wanted)
      that.setData({ checking: false, shortage: check.ok ? null : { problems: check.problems } })
    })
  },

  updateCount(id, delta) {
    const current = cart.readCart(this.kitchenId)
    const entry = current[id]
    if (!entry) return
    const next = entry.count + delta
    if (next <= 0) {
      delete current[id]
    } else {
      entry.count = next
      current[id] = entry
    }
    cart.writeCart(this.kitchenId, current)
    this.refresh()
    this.checkStock()
  },

  increase(event) {
    this.updateCount(Number(event.currentTarget.dataset.id), 1)
  },

  decrease(event) {
    this.updateCount(Number(event.currentTarget.dataset.id), -1)
  },

  onNameInput(event) {
    const that = this
    this.setData({ dinerName: event.detail.value }, function () {
      that.buildSummary()
    })
  },

  onNoteInput(event) {
    const that = this
    this.setData({ note: event.detail.value }, function () {
      that.buildSummary()
    })
  },

  // 这一单归哪个厨房：优先用页面参数，兜底再看清单里记下的厨房。
  resolveKitchenId(list) {
    if (this.kitchenId) return Promise.resolve(this.kitchenId)
    const known = list
      .map(function (item) {
        return item.kitchen_id
      })
      .filter(function (value) {
        return !!value
      })[0]
    if (known) return Promise.resolve(known)
    return Promise.reject(new Error('没能识别这些菜属于哪个厨房，请从菜单页重新进入'))
  },

  submitOrder() {
    const that = this
    if (this.data.submitting) return
    const list = cart.toList(cart.readCart(this.kitchenId))
    if (!list.length) {
      wx.showToast({ title: '还没有点菜', icon: 'none' })
      return
    }
    const name = String(this.data.dinerName || '').trim()
    if (!name) {
      wx.showToast({ title: '请先填一下你的称呼', icon: 'none' })
      return
    }
    try {
      meal.validateSchedule({
        orderDate: this.data.orderDate,
        mealTimeType: this.data.mealType,
        mealTimeStart: this.data.timeStart,
        mealTimeEnd: this.data.timeEnd,
      })
    } catch (err) {
      wx.showModal({ title: '请调整就餐时间', content: err.message, showCancel: false })
      return
    }
    if (this.data.shortage) {
      wx.showModal({
        title: '有几样食材不够',
        content: '先把提示里说的那几道减掉或换成别的菜，再发给大厨吧。',
        showCancel: false,
      })
      return
    }
    this.setData({ submitting: true })
    this.resolveKitchenId(list)
      .then(function (kitchenId) {
        return api.createOrder({
          kitchenId: kitchenId,
          dinerName: name,
          note: that.data.note,
          orderDate: that.data.orderDate,
          mealTimeType: that.data.mealType,
          mealTimeStart: that.data.timeStart,
          mealTimeEnd: that.data.timeEnd,
          items: list.map(function (item) {
            return { dish_id: item.id, dish_name: item.name, quantity: item.count }
          }),
        })
      })
      .then(function (order) {
        cart.writeDinerName(name)
        cart.clear(that.kitchenId)
        that.setData({ submitting: false })
        wx.showToast({ title: '已发给大厨', icon: 'success' })
        setTimeout(function () {
          const target = order && order.id
            ? '/pages/order-detail/order-detail?id=' + order.id
            : '/pages/home/home'
          wx.redirectTo({ url: target })
        }, 800)
      })
      .catch(function (err) {
        that.setData({ submitting: false })
        wx.showModal({ title: '发送失败', content: api.friendly(err), showCancel: false })
      })
  },

  copySummary() {
    if (!this.data.items.length) {
      wx.showToast({ title: '还没有点菜', icon: 'none' })
      return
    }
    wx.setClipboardData({
      data: this.data.summary,
      success() {
        wx.showToast({ title: '清单已复制', icon: 'success' })
      },
    })
  },

  clearAll() {
    const that = this
    if (!this.data.items.length) return
    wx.showModal({
      title: '清空点菜清单？',
      content: '只会清空这份清单，菜单里的菜不受影响。',
      confirmColor: '#D64545',
      success(res) {
        if (!res.confirm) return
        cart.clear(that.kitchenId)
        that.refresh()
        that.checkStock()
      },
    })
  },

  goMenu() {
    if (this.kitchenId) {
      wx.redirectTo({ url: '/pages/menu/menu?kitchenId=' + this.kitchenId })
      return
    }
    wx.navigateBack()
  },
})
