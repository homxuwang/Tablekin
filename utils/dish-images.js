const MAX_IMAGES = 9

function unique(list) {
  return (list || []).filter((path, index, all) =>
    typeof path === 'string' && path.trim() && all.indexOf(path) === index)
}

function cover(list, path) {
  const result = unique(list)
  if (result.indexOf(path) < 0) return result
  return [path].concat(result.filter(item => item !== path))
}

function paths(dish) {
  const row = dish || {}
  const result = unique(Array.isArray(row.image_paths) ? row.image_paths : [])
  if (!result.length && row.image_path) return unique([row.image_path])
  return cover(result, row.image_path)
}

function fields(list) {
  const result = unique(list)
  if (result.length > MAX_IMAGES) throw new Error('每道菜最多上传9张图片')
  return { image_paths: result, image_path: result[0] || null }
}

module.exports = { MAX_IMAGES, paths, cover, fields }
