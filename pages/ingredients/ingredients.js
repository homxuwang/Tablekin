const api = require('../../utils/api')
const { confirmDelete } = require('../../utils/confirm-delete')

function emptyForm() {
  return { id: 0, name: '', unit: '份', stock: '', alert_threshold: '' }
}

function confirmedStockFailure(error) {
  const message = String((error && (error.message || error.details)) || '').split(':')[0].trim()
  return ['not_signed_in', 'ingredient_not_found', 'not_kitchen_member', 'mode_invalid', 'value_invalid',
    'expected_stock_required', 'stock_changed', 'stock_negative', 'stock_too_large', 'no_change', 'request_id_reused'].indexOf(message) >= 0
}

function stockRequestId(id) { return 'stock-' + id + '-' + Date.now() + '-' + Math.random().toString(36).slice(2, 12) }

function formatTime(value) {
  if (!value) return ''
  const date = new Date(value)
  if (isNaN(date.getTime())) return ''
  const pad = function (n) {
    return n < 10 ? '0' + n : String(n)
  }
  return (date.getMonth() + 1) + '月' + date.getDate() + '日 ' + pad(date.getHours()) + ':' + pad(date.getMinutes())
}

function decorate(item) {
  const stock = Number(item.stock || 0)
  const threshold = Number(item.alert_threshold || 0)
  return Object.assign({}, item, {
    stockNum: stock,
    stockText: String(api.round1(stock)),
    unit: item.unit || '份',
    alertText: String(api.round1(threshold)),
    low: stock <= 0 || (threshold > 0 && stock <= threshold),
  })
}

Page({
  data: {
    kitchenId: 0,
    loading: true,
    error: '',
    list: [],
    lowCount: 0,
    showForm: false,
    form: emptyForm(),
    saving: false,
    stockBusy: false,
    pendingStock: null,
    logsFor: 0,
    logsName: '',
    logsLoading: false,
    logs: [],
  },

  onLoad(options) {
    this.kitchenId = Number((options && options.kitchenId) || 0)
    this.setData({ kitchenId: this.kitchenId })
  },

  onShow() {
    if (!this.kitchenId) {
      this.setData({ loading: false, error: '没有指定厨房，请从首页重新进入' })
      return
    }
    this.load()
  },

  onPullDownRefresh() {
    this.load().then(function () {
      wx.stopPullDownRefresh()
    })
  },

  load() {
    const that = this
    this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function (user) {
        that._stockStorageKey = 'pending-stock-' + user.id + '-' + that.kitchenId
        const pending = wx.getStorageSync(that._stockStorageKey)
        that.setData({ pendingStock: pending || null })
        return api.fetchIngredients({ kitchenId: that.kitchenId })
      })
      .then(function (rows) {
        const list = rows.map(decorate)
        that.setData(
          {
            list: list,
            lowCount: list.filter(function (item) {
              return item.low
            }).length,
            loading: false,
            error: '',
          },
          function () {
            if (that.data.logsFor) that.reloadLogs(that.data.logsFor)
          }
        )
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  reloadLogs(id) {
    const that = this
    const target = this.data.list.filter(function (item) {
      return item.id === id
    })[0]
    if (!target) {
      this.setData({ logsFor: 0, logs: [] })
      return
    }
    api.fetchStockLogs(id).then(function (rows) {
      that.setData({ logs: that.decorateLogs(rows) })
    })
  },

  decorateLogs(rows) {
    return rows.map(function (row) {
      const change = Number(row.change || 0)
      return Object.assign({}, row, {
        changeText: (change > 0 ? '+' : '') + api.round1(change),
        positive: change > 0,
        balanceText: '余 ' + api.round1(row.balance),
        timeText: formatTime(row.created_at),
      })
    })
  },

  toggleForm() {
    if (this.data.saving) return
    const next = !this.data.showForm
    this.setData({ showForm: next, form: next ? this.data.form : emptyForm() })
  },

  openNew() {
    if (this.data.saving) return
    this.setData({ showForm: true, form: emptyForm() })
    wx.pageScrollTo({ scrollTop: 0, duration: 200 })
  },

  openEdit(event) {
    if (this.data.saving) return
    const id = Number(event.currentTarget.dataset.id)
    const target = this.data.list.filter(function (item) {
      return item.id === id
    })[0]
    if (!target) return
    this.setData({
      showForm: true,
      form: {
        id: target.id,
        name: target.name,
        unit: target.unit,
        stock: String(target.stockNum),
        alert_threshold: Number(target.alert_threshold || 0) ? String(api.round1(target.alert_threshold)) : '',
      },
    })
    wx.pageScrollTo({ scrollTop: 0, duration: 200 })
  },

  onInput(event) {
    if (this.data.saving) return
    const patch = {}
    patch['form.' + event.currentTarget.dataset.field] = event.detail.value
    this.setData(patch)
  },

  saveForm() {
    const that = this
    if (this.data.saving || this.data.stockBusy || this._stockDialog) return
    if (this.data.pendingStock) { wx.showToast({ title: '请先确认上次库存操作', icon: 'none' }); return }
    const form = Object.assign({}, this.data.form)
    const name = String(form.name || '').trim()
    if (!name) {
      wx.showToast({ title: '请填写食材名称', icon: 'none' })
      return
    }
    const payload = {
      name: name,
      unit: String(form.unit || '').trim() || '份',
      alert_threshold: Number(form.alert_threshold || 0) || 0,
    }
    this.setData({ saving: true })
    let task
    if (form.id) {
      task = api.updateIngredient(form.id, payload)
    } else {
      payload.kitchen_id = this.kitchenId
      payload.stock = Number(form.stock || 0) || 0
      payload.sort_order = this.data.list.length
      payload.is_public = true
      task = api.createIngredient(payload)
    }
    task
      .then(function () {
        that.setData({ saving: false, showForm: false, form: emptyForm() })
        wx.showToast({ title: '已保存', icon: 'success' })
        that.load()
      })
      .catch(function (err) {
        that.setData({ saving: false })
        if (err.ingredient) {
          that.setData({ form: Object.assign({}, form, { id: err.ingredient.id }) })
          const operation = {
            ingredientId: err.ingredient.id, ingredientName: name,
            mode: 'recount', value: err.initialStock, expectedStock: 0,
            reason: '新建食材初始库存', requestId: 'initial-' + err.ingredient.id,
          }
          if (!confirmedStockFailure(err.cause)) {
            that.setData({ pendingStock: operation })
            if (that._stockStorageKey) wx.setStorageSync(that._stockStorageKey, operation)
          }
          that.load()
        }
        wx.showModal({ title: '保存失败', content: api.friendly(err), showCancel: false })
      })
  },

  findById(id) {
    return this.data.list.filter(function (item) {
      return item.id === id
    })[0]
  },

  stockIn(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    const target = this.findById(id)
    if (!target) return
    if (this.data.stockBusy || this.data.saving || this._stockDialog) return
    if (this.data.pendingStock) { wx.showToast({ title: '请先确认上次库存操作', icon: 'none' }); return }
    this._stockDialog = true
    wx.showModal({
      title: '入库：' + target.name,
      editable: true,
      placeholderText: '买入数量，单位「' + target.unit + '」',
      success(res) {
        that._stockDialog = false
        if (!res.confirm) return
        const raw = String(res.content || '').trim()
        const amount = Number(raw)
        if (!raw || !Number.isFinite(amount) || amount <= 0) {
          wx.showToast({ title: '请输入大于 0 的数量', icon: 'none' })
          return
        }
        return that.runStock({
            ingredientId: id,
            ingredientName: target.name,
            mode: 'delta',
            value: amount,
            reason: '入库',
            requestId: stockRequestId(id),
          })
      },
      fail() { that._stockDialog = false },
    })
  },

  recount(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    const target = this.findById(id)
    if (!target) return
    if (this.data.stockBusy || this.data.saving || this._stockDialog) return
    if (this.data.pendingStock) { wx.showToast({ title: '请先确认上次库存操作', icon: 'none' }); return }
    this._stockDialog = true
    wx.showModal({
      title: '盘点：' + target.name,
      editable: true,
      placeholderText: '实际还剩多少（' + target.unit + '）',
      success(res) {
        that._stockDialog = false
        if (!res.confirm) return
        const raw = String(res.content || '').trim()
        const actual = Number(raw)
        if (!raw || !Number.isFinite(actual) || actual < 0) {
          wx.showToast({ title: '请输入不小于 0 的数字', icon: 'none' })
          return
        }
        // 盘点走 recount：把「实际值 + 盘点前页面上的值」一起交给服务端核对，
        // 期间大厨接单扣了库存就会提示刷新，而不是拿旧数字覆盖掉。
        return that.runStock({
            ingredientId: id,
            ingredientName: target.name,
            mode: 'recount',
            value: actual,
            expectedStock: target.stockNum,
            reason: '盘点校正',
            requestId: stockRequestId(id),
          })
      },
      fail() { that._stockDialog = false },
    })
  },

  clearPendingStock() {
    if (this._stockStorageKey) wx.removeStorageSync(this._stockStorageKey)
    this.setData({ pendingStock: null })
  },

  async runStock(operation) {
    if (this.data.stockBusy || this.data.saving) return
    this.setData({ stockBusy: true, pendingStock: operation })
    wx.showLoading({ title: '记录中', mask: true })
    try {
      // 发请求前保存：超时、离开页面或重启后仍可用同一个编号重试。
      if (this._stockStorageKey) wx.setStorageSync(this._stockStorageKey, operation)
      await api.adjustStock(operation)
      this.clearPendingStock()
      wx.showToast({ title: '库存操作已确认', icon: 'success' })
      await this.load()
    } catch (err) {
      if (confirmedStockFailure(err)) {
        this.clearPendingStock()
        await this.load()
      }
      wx.showModal({
        title: confirmedStockFailure(err) ? '操作未执行' : '库存操作待确认',
        content: api.friendly(err) + (confirmedStockFailure(err) ? '' : '。请使用页面上的“重试确认”，同一次操作不会重复记账。'),
        showCancel: false,
      })
    } finally {
      wx.hideLoading()
      this.setData({ stockBusy: false })
    }
  },

  retryStock() {
    if (!this.data.pendingStock || this.data.stockBusy) return Promise.resolve()
    return this.runStock(this.data.pendingStock)
  },

  showLogs(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    const target = this.findById(id)
    if (!target) return
    this.setData({ logsFor: id, logsName: target.name, logsLoading: true, logs: [] })
    api
      .fetchStockLogs(id)
      .then(function (rows) {
        that.setData({ logsLoading: false, logs: that.decorateLogs(rows) })
      })
      .catch(function (err) {
        that.setData({ logsLoading: false, logsFor: 0 })
        wx.showModal({ title: '明细加载失败', content: api.friendly(err), showCancel: false })
      })
  },

  closeLogs() {
    this.setData({ logsFor: 0, logsName: '', logs: [] })
  },

  async removeItem(event) {
    if (this.data.stockBusy || this.data.saving || this._stockDialog) return
    if (this.data.pendingStock) { wx.showToast({ title: '请先确认上次库存操作', icon: 'none' }); return }
    const id = Number(event.currentTarget.dataset.id)
    const target = this.findById(id)
    if (!target) return
    this._stockDialog = true
    try {
      if (!await confirmDelete({ title: '删除食材「' + target.name + '」？', content: '相关菜品会取消这条用料关联，菜品本身保留。' }, wx)) return
      await api.deleteIngredient(id)
      wx.showToast({ title: '已删除', icon: 'success' })
      await this.load()
    } catch (err) {
      wx.showModal({ title: '删除失败', content: api.friendly(err), showCancel: false })
    } finally {
      this._stockDialog = false
    }
  },

  goBack() {
    wx.navigateBack()
  },
})
