const api = require('../../utils/api')
const dishImages = require('../../utils/dish-images')
const dishTags = require('../../utils/dish-tags')
const haptics = require('../../utils/haptics')
const recent = require('../../utils/recent')

const HISTORY_KEY = 'recent_search_keywords'
const MAX_HISTORY = 8

function readHistory() {
  try {
    const raw = wx.getStorageSync(HISTORY_KEY)
    return Array.isArray(raw) ? raw.filter(Boolean).slice(0, MAX_HISTORY) : []
  } catch (e) {
    return []
  }
}

function saveHistory(keyword) {
  const clean = String(keyword || '').trim()
  if (!clean) return readHistory()
  const list = readHistory().filter(function (item) {
    return item !== clean
  })
  list.unshift(clean)
  const next = list.slice(0, MAX_HISTORY)
  try {
    wx.setStorageSync(HISTORY_KEY, next)
  } catch (e) {
    // 存储异常不影响搜索
  }
  return next
}

function decorateKitchen(kitchen, mineIds) {
  const isMine = !!mineIds[kitchen.id]
  return Object.assign({}, kitchen, {
    initial: String(kitchen.name || '厨').slice(0, 1),
    scopeText: kitchen.is_public ? '公开' : '私密',
    mineText: isMine ? '我参与的' : '',
  })
}

Page({
  data: {
    mode: 'dish',
    keyword: '',
    focus: true,
    loading: false,
    searched: false,
    error: '',
    kitchenId: 0,
    kitchenName: '',
    scope: 'current',
    dishes: [],
    kitchens: [],
    allTags: [],
    pickedTags: [],
    tagMode: 'all',
    history: [],
  },

  onLoad(options) {
    const opts = options || {}
    const passed = Number(opts.kitchenId || 0)
    const kitchenId = passed || recent.readLastKitchen()
    const mode = opts.mode === 'kitchen' ? 'kitchen' : 'dish'
    // 没有「本厨房」可搜时默认落到「所有厨房」，免得点进去只有一个空结果
    const scope = kitchenId ? 'current' : 'all'
    this.setData({ kitchenId: kitchenId, mode: mode, scope: scope, history: readHistory() })
    if (kitchenId) this.loadKitchenName(kitchenId)
    this.loadTags()
  },

  pickHistory(event) {
    const word = String(event.currentTarget.dataset.word || '').trim()
    if (!word) return
    haptics.light()
    this.setData({ keyword: word, focus: false })
    this.runSearch()
  },

  clearHistory() {
    haptics.light()
    try {
      wx.removeStorageSync(HISTORY_KEY)
    } catch (e) {
      // ignore
    }
    this.setData({ history: [] })
  },

  // ---------- 标签 ----------

  // 标签云跟着搜索范围走：本厨房的就只列这个厨房用过的，所有厨房的列出全部可见的
  loadTags() {
    const that = this
    const kitchenId = this.data.scope === 'current' ? this.data.kitchenId : 0
    this.tagSeq = (this.tagSeq || 0) + 1
    const seq = this.tagSeq
    api
      .listKitchenTags(kitchenId)
      .then(function (rows) {
        if (seq !== that.tagSeq) return
        that.rawTags = api.asArray(rows)
        that.applyTags(that.data.pickedTags)
      })
      .catch(function () {
        // 标签只是辅助筛选项，拿不到就整块不显示
        if (seq !== that.tagSeq) return
        that.rawTags = []
        that.applyTags([])
      })
  },

  applyTags(picked) {
    const rows = this.rawTags || []
    this.setData({
      pickedTags: picked,
      allTags: rows.map(function (item) {
        return Object.assign({}, item, { picked: picked.indexOf(item.name) >= 0 })
      }),
    })
  },

  pickTag(event) {
    const name = event.currentTarget.dataset.name
    const picked = this.data.pickedTags.slice()
    const at = picked.indexOf(name)
    if (at >= 0) picked.splice(at, 1)
    else picked.push(name)
    this.applyTags(picked)
    this.runSearch()
  },

  switchTagMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode === this.data.tagMode) return
    this.setData({ tagMode: mode })
    this.runSearch()
  },

  loadKitchenName(kitchenId) {
    const that = this
    api
      .fetchKitchen(kitchenId)
      .then(function (kitchen) {
        if (kitchen && kitchen.id) that.setData({ kitchenName: kitchen.name || '' })
      })
      .catch(function () {
        // 拿不到名字就退化成「本厨房」，搜索照常
      })
  },

  // 我参与的厨房只查一次，用来在结果里标出「我参与的」
  myKitchenIds() {
    if (!this.mineIdsPromise) {
      this.mineIdsPromise = api
        .fetchMyKitchens()
        .then(function (rows) {
          const map = {}
          api.asArray(rows).forEach(function (item) {
            map[item.id] = true
          })
          return map
        })
        .catch(function () {
          return {}
        })
    }
    return this.mineIdsPromise
  },

  onShareAppMessage() {
    return { title: '吃好喝好 · 搜一搜', path: '/pages/home/home' }
  },

  onInput(event) {
    this.setData({ keyword: event.detail.value })
    this.scheduleSearch()
  },

  scheduleSearch() {
    const that = this
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(function () {
      that.runSearch()
    }, 300)
  },

  switchMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode === this.data.mode) return
    this.setData({ mode: mode, dishes: [], kitchens: [], searched: false })
    this.runSearch()
  },

  pickScope(event) {
    const scope = event.currentTarget.dataset.scope
    if (scope === this.data.scope) return
    if (scope === 'current' && !this.data.kitchenId) {
      wx.showToast({ title: '还没有选中的厨房，先去首页挑一个', icon: 'none' })
      return
    }
    this.setData({ scope: scope })
    this.loadTags()
    this.runSearch()
  },

  runSearch() {
    const that = this
    const keyword = String(this.data.keyword || '').trim()
    const tags = dishTags.clean(this.data.pickedTags)
    if (this.timer) clearTimeout(this.timer)
    // 只输菜名、只选标签、两者都给，这三种都能搜
    if (!keyword && !tags.length) {
      this.setData({ dishes: [], kitchens: [], searched: false, loading: false, error: '' })
      return
    }
    const patch = { loading: true, error: '', searched: true }
    if (keyword) patch.history = saveHistory(keyword)
    this.setData(patch)
    // 打字快时会有多个请求在路上，只认最后一次
    this.seq = (this.seq || 0) + 1
    const seq = this.seq
    const guard = function (payload) {
      return seq === that.seq ? payload : null
    }

    if (this.data.mode === 'kitchen') {
      Promise.all([api.searchKitchens(keyword), this.myKitchenIds()])
        .then(function (result) {
          const payload = guard({ rows: result[0], mine: result[1] })
          if (!payload) return
          that.setData({
            kitchens: api.asArray(payload.rows).map(function (item) {
              return decorateKitchen(item, payload.mine)
            }),
            loading: false,
          })
        })
        .catch(function (err) {
          if (!guard(true)) return
          that.setData({ loading: false, error: api.friendly(err) })
        })
      return
    }

    const kitchenId = this.data.scope === 'current' ? this.data.kitchenId : 0
    api
      .searchDishes({
        kitchenId: kitchenId,
        keyword: keyword,
        tags: tags,
        tagMode: this.data.tagMode,
      })
      .then(function (rows) {
        const dishes = api.asArray(rows)
        const ids = []
        dishes.forEach(function (dish) {
          if (dish.kitchen_id && ids.indexOf(dish.kitchen_id) < 0) ids.push(dish.kitchen_id)
        })
        return Promise.all([
          ids.length
            ? api.fetchKitchensByIds(ids).catch(function () {
                return []
              })
            : Promise.resolve([]),
          api.signImageUrls(
            dishes.map(function (dish) {
              return dishImages.paths(dish)[0]
            })
          ),
        ]).then(function (extra) {
          return guard({ dishes: dishes, kitchens: extra[0], urls: extra[1] || {} })
        })
      })
      .then(function (payload) {
        if (!payload) return
        const names = {}
        api.asArray(payload.kitchens).forEach(function (kitchen) {
          names[kitchen.id] = kitchen.name || ''
        })
        that.setData({
          dishes: payload.dishes.map(function (dish) {
            return Object.assign({}, dish, {
              initial: String(dish.name || '菜').slice(0, 1),
              imageUrl: payload.urls[dishImages.paths(dish)[0]] || '',
              kitchenName: names[dish.kitchen_id] || '',
              tagList: dishTags.tags(dish),
            })
          }),
          loading: false,
        })
      })
      .catch(function (err) {
        if (!guard(true)) return
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  clearKeyword() {
    this.setData({ keyword: '', focus: true })
    // 选了标签的话，清掉菜名还应该按标签继续出结果
    this.runSearch()
  },

  openDish(event) {
    const id = Number(event.currentTarget.dataset.id)
    const kitchenId = Number(event.currentTarget.dataset.kitchen) || 0
    wx.navigateTo({ url: '/pages/dish/dish?id=' + id + '&kitchenId=' + kitchenId })
  },

  openKitchen(event) {
    wx.navigateTo({ url: '/pages/menu/menu?kitchenId=' + Number(event.currentTarget.dataset.id) })
  },

  goBack() {
    if (getCurrentPages().length > 1) {
      wx.navigateBack()
      return
    }
    wx.switchTab({ url: '/pages/home/home' })
  },
})
