// 防误触的二次确认，服务端权限仍由现有 RLS/RPC 判断。
async function confirmDelete(options, wxClient) {
  const approved = await new Promise(resolve => {
    wxClient.showModal({
      title: options.title,
      content: options.content,
      confirmText: '继续验证',
      confirmColor: '#D64545',
      success: result => resolve(!!result.confirm),
      fail: () => resolve(false),
    })
  })
  if (!approved) return false
  const code = String(Math.floor(1000 + Math.random() * 9000))
  return new Promise(resolve => {
    wxClient.showModal({
      // 将校验数字放在标题，避免原生可编辑弹窗把 content 用作输入内容。
      title: '输入 ' + code + ' 确认删除',
      editable: true,
      placeholderText: '输入上方四位数字',
      confirmText: '验证删除',
      confirmColor: '#D64545',
      success(result) {
        if (!result.confirm) { resolve(false); return }
        const matches = String(result.content || '').trim() === code
        if (!matches) wxClient.showToast({ title: '数字不匹配，未删除', icon: 'none' })
        resolve(matches)
      },
      fail() { resolve(false) },
    })
  })
}

module.exports = { confirmDelete }
