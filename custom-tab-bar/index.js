const api = require('../utils/api')
const refresh = require('../utils/live-refresh')

Component({
  data: {
    active: 0,
    unreadCount: 0,
    list: [
      { pagePath: '/pages/home/home', text: '点菜', icon: 'eat' },
      { pagePath: '/pages/chef/chef', text: '下厨', icon: 'cook' },
      { pagePath: '/pages/orders/orders', text: '订单', icon: 'order' },
    ],
  },

  pageLifetimes: {
    show() {
      refresh.start(this, () => this.refreshBadge())
      if (this._badgeRequest) this._badgeRequest.then(() => {
        if (this._refreshVisible) this.refreshBadge()
      })
      else this.refreshBadge()
    },
    hide() { refresh.stop(this) },
  },
  lifetimes: { detached() { refresh.stop(this) } },

  methods: {
    setUnreadCount(count) {
      this._badgeVersion = (this._badgeVersion || 0) + 1
      this.setData({ unreadCount: count })
    },
    refreshBadge() {
      const version = this._badgeVersion || 0
      const epoch = this._refreshEpoch || 0
      return refresh.singleFlight(this, '_badgeRequest', () => api.fetchUnreadNotificationCount()
        .then(count => {
          if (this._refreshVisible && version === (this._badgeVersion || 0) && epoch === (this._refreshEpoch || 0)) {
            this.setData({ unreadCount: count })
          }
        })
        .catch(() => {}))
    },
    onTap(event) {
      const index = Number(event.currentTarget.dataset.index)
      const item = this.data.list[index]
      if (!item || index === this.data.active) return
      wx.switchTab({ url: item.pagePath })
    },
  },
})
