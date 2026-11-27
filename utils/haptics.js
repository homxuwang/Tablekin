// 轻量触觉反馈：在真机上提供轻微震动，测试环境或不支持设备上静默忽略。
function light() {
  try {
    if (typeof wx !== 'undefined' && typeof wx.vibrateShort === 'function') {
      wx.vibrateShort({ type: 'light' })
    }
  } catch (err) {
    // 忽略不支持的设备
  }
}

module.exports = { light }
