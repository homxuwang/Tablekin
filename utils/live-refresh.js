// 一个可见页面一个刷新器，隐藏或销毁时停止；业务操作期间跳过刷新。
function stop(owner) {
  owner._refreshEpoch = (owner._refreshEpoch || 0) + 1
  owner._refreshVisible = false
  if (owner._refreshTimer) clearInterval(owner._refreshTimer)
  owner._refreshTimer = null
}
function start(owner, task) {
  stop(owner)
  owner._refreshVisible = true
  owner._refreshTimer = setInterval(function () {
    const data = owner.data || {}
    if (!owner._refreshVisible || data.busy || data.busyId || data.noticesBusy || data.loading) return
    Promise.resolve().then(function () {
      if (owner._refreshVisible) return task()
    }).catch(function (error) { console.warn('[刷新失败]', error && error.message) })
  }, 20000)
}
function singleFlight(owner, key, task) {
  if (owner[key]) return owner[key]
  const result = Promise.resolve().then(task)
  owner[key] = result.then(function (value) {
    owner[key] = null
    return value
  }, function (error) {
    owner[key] = null
    throw error
  })
  return owner[key]
}
module.exports = { start, stop, singleFlight }
