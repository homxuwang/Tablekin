const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const root = path.resolve(__dirname, '..')

function load(file, overrides = {}, globals = {}) {
  const filename = path.join(root, file)
  const sandbox = {
    module: { exports: {} }, console, setTimeout, clearTimeout, setInterval, clearInterval,
    require(name) {
      if (Object.hasOwn(overrides, name)) return overrides[name]
      return require(name.startsWith('.') ? path.resolve(path.dirname(filename), name) : name)
    },
    ...globals,
  }
  vm.runInNewContext(fs.readFileSync(filename, 'utf8'), sandbox, { filename })
  return sandbox.module.exports
}

function apiHarness() {
  const calls = []
  const cloud = {
    auth: { getSession: async () => ({ data: { user: { id: 'diner' } } }) },
    database: {
      rpc: async (name, args) => {
        calls.push({ name, args })
        return { data: { ok: true, order_id: 31, marked: 2 } }
      },
    },
  }
  return { api: load('utils/api.js', { './cloud': { cloud } }), calls, cloud }
}

function pageHarness(file, api, extra = {}) {
  let spec
  const calls = []
  const storage = new Map()
  const wx = {
    showToast: args => calls.push(['toast', args]),
    showModal: args => calls.push(['modal', args]),
    showLoading: args => calls.push(['loading', args]), hideLoading() {},
    getStorageSync: key => storage.get(key),
    setStorageSync: (key, value) => storage.set(key, structuredClone(value)),
    removeStorageSync: key => storage.delete(key),
    navigateTo: args => calls.push(['navigate', args]),
    navigateBack() {},
    setNavigationBarTitle() {}, stopPullDownRefresh() {},
  }
  load(file, { '../../utils/api': api, ...extra }, {
    Page(value) { spec = value }, wx,
    getApp: () => ({ globalData: {} }),
  })
  const page = { ...spec, data: structuredClone(spec.data) }
  page.setData = (patch, done) => { Object.assign(page.data, patch); if (done) done.call(page) }
  return { page, calls, storage, wx }
}

module.exports = { root, load, apiHarness, pageHarness }
