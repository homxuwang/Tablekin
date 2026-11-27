function move(rows, id, target) {
  const result = rows.slice()
  const from = result.findIndex(row => String(row.id) === String(id))
  if (from < 0 || !Number.isFinite(target)) return result
  const to = Math.max(0, Math.min(result.length - 1, Math.floor(target)))
  const item = result.splice(from, 1)[0]
  result.splice(to, 0, item)
  return result
}

function sameIds(a, b) {
  return a.length === b.length && a.every((id, index) => String(id) === String(b[index]))
}

function targetIndex(clientY, top, scrollTop, rowHeight, count) {
  if (!count || rowHeight <= 0) return 0
  return Math.max(0, Math.min(count - 1, Math.floor((clientY - top + scrollTop) / rowHeight)))
}

module.exports = { move, sameIds, targetIndex }
