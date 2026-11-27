const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const root = path.resolve(__dirname, '..')
let checked = 0
// 页面 JS 会 require 各类 utils。能独立加载的真实模块直接挂进去，
// 加载不了的（api 依赖云端 SDK，而包内已不再随 npm 安装）退回空对象，
// 这样新增工具模块时无需再回来改这份清单。
const utilsModules = {}
for (const entry of fs.readdirSync(path.join(root, 'utils'))) {
  if (!entry.endsWith('.js')) continue
  const name = entry.slice(0, -3)
  try {
    const mod = require(path.join(root, 'utils', name))
    utilsModules['../../utils/' + name] = mod
    utilsModules['../utils/' + name] = mod
  } catch (err) {
    /* 依赖云端 SDK 或 wx 全局的模块跳过 */
  }
}
function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const filename = path.join(directory, entry.name)
    return entry.isDirectory() ? walk(filename) : [filename]
  })
}
const files = ['app.js', 'app.json', 'project.config.json'].map(file => path.join(root, file))
for (const folder of ['pages', 'custom-tab-bar', 'utils']) files.push(...walk(path.join(root, folder)))
for (const filename of files) {
  const source = fs.readFileSync(filename, 'utf8')
  if (filename.endsWith('.js')) new vm.Script(source, { filename })
  if (filename.endsWith('.json')) JSON.parse(source)
  if (!filename.endsWith('.wxml')) { checked++; continue }
  let spec
  vm.runInNewContext(fs.readFileSync(filename.replace('.wxml', '.js'), 'utf8'), {
    require: name => utilsModules[name] || {}, module: { exports: {} },
    Page: value => { spec = value }, Component: value => { spec = value.methods },
  })
  for (const match of source.matchAll(/(?:bind|catch)(?::)?[a-z]+\s*=\s*"([a-zA-Z_$][\w$]*)"/g)) {
    if (!spec || typeof spec[match[1]] !== 'function') throw new Error(filename + ': 缺少事件方法 ' + match[1])
  }
  const stack = []
  for (const match of source.matchAll(/<\/?([\w-]+)((?:[^>"']|"[^"]*"|'[^']*')*)>/g)) {
    if (match[0].startsWith('</')) {
      if (stack.pop() !== match[1]) throw new Error(filename + ': 标签未配对 ' + match[0])
    } else if (!match[2].trim().endsWith('/')) stack.push(match[1])
  }
  if (stack.length) throw new Error(filename + ': 未关闭标签 ' + stack.join(', '))
  checked++
}
const app = JSON.parse(fs.readFileSync(path.join(root, 'app.json'), 'utf8'))
for (const page of app.pages) {
  for (const extension of ['js', 'json', 'wxml', 'wxss']) {
    if (!fs.existsSync(path.join(root, page + '.' + extension))) throw new Error('缺少页面文件 ' + page + '.' + extension)
  }
}
console.log('已检查 ' + checked + ' 个文件：JS 语法、JSON、WXML 标签与事件绑定、页面注册均通过。')
