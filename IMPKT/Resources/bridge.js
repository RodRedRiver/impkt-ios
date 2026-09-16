/* Web Bluetooth, implemented on top of CoreBluetooth, for the pilot page.
 *
 * The page is not modified to run in this app. It calls navigator.bluetooth the
 * same way it does in Chrome; this file is what navigator.bluetooth IS on iOS,
 * where Apple ships no Web Bluetooth at all. Everything below is a thin
 * translation into messages the Swift side answers, and back into the objects
 * and events the page already expects.
 *
 * Injected at document start, before any page script runs, so the page never
 * sees a window without it.
 *
 * Deliberately not a general-purpose polyfill. It implements the surface the
 * pilot page actually uses, which is: getDevices, requestDevice, requestLEScan,
 * per-device watchAdvertisements, connect, getPrimaryService, getCharacteristic,
 * startNotifications, readValue, writeValue, and the two events that carry the
 * work, characteristicvaluechanged and gattserverdisconnected. A call outside
 * that set throws rather than returning something plausible, because a silent
 * half-answer here would look like a firmware fault on the bench.
 */
(function () {
  'use strict';
  if (window.navigator.bluetooth && !window.__impktShim) return;   // real one wins

  var seq = 1;
  var pending = {};          // id -> {resolve, reject}
  var devices = {};          // deviceId -> BluetoothDevice
  var scanTargets = [];      // things listening for advertisementreceived

  function send(op, args) {
    return new Promise(function (resolve, reject) {
      var id = seq++;
      pending[id] = { resolve: resolve, reject: reject };
      try {
        window.webkit.messageHandlers.impkt.postMessage({ id: id, op: op, args: args || {} });
      } catch (e) {
        delete pending[id];
        reject(new Error('the app bridge is not there: ' + e));
      }
    });
  }

  function b64ToDataView(b64) {
    var raw = atob(b64 || '');
    var buf = new ArrayBuffer(raw.length);
    var view = new Uint8Array(buf);
    for (var i = 0; i < raw.length; i++) view[i] = raw.charCodeAt(i);
    return new DataView(buf);
  }

  function dataToB64(value) {
    var bytes;
    if (value instanceof ArrayBuffer) bytes = new Uint8Array(value);
    else if (value && value.buffer) bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    else bytes = new Uint8Array(value || []);
    var s = '';
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s);
  }

  /* A 16-bit UUID and its 128-bit form are the same characteristic, and the page
     writes them in whichever form is natural, so everything is compared in one
     canonical shape. Getting this wrong shows up as "the wrap connected but has
     no characteristics", which reads as a firmware fault and is not one. */
  function canon(uuid) {
    var u = String(uuid).toLowerCase();
    if (/^0x[0-9a-f]{1,4}$/.test(u)) u = parseInt(u, 16).toString(16);
    if (/^[0-9a-f]{1,4}$/.test(u)) {
      while (u.length < 4) u = '0' + u;
      u = '0000' + u + '-0000-1000-8000-00805f9b34fb';
    }
    return u;
  }

  /* ---- events ---------------------------------------------------------- */

  function Emitter() { this._l = {}; }
  Emitter.prototype.addEventListener = function (type, fn) {
    (this._l[type] = this._l[type] || []).push(fn);
  };
  Emitter.prototype.removeEventListener = function (type, fn) {
    var a = this._l[type] || [];
    var i = a.indexOf(fn);
    if (i >= 0) a.splice(i, 1);
  };
  Emitter.prototype.dispatchEvent = function (ev) {
    var a = (this._l[ev.type] || []).slice();
    for (var i = 0; i < a.length; i++) {
      try { a[i].call(this, ev); } catch (e) { console.error(e); }
    }
    return true;
  };

  /* ---- GATT ------------------------------------------------------------ */

  function Characteristic(device, service, info) {
    Emitter.call(this);
    this.uuid = info.uuid;
    this.service = service;
    this.properties = info.properties || {};
    this.value = null;
    this._device = device;
  }
  Characteristic.prototype = Object.create(Emitter.prototype);

  Characteristic.prototype.readValue = function () {
    var self = this;
    return send('read', { device: this._device.id, characteristic: this.uuid })
      .then(function (r) {
        self.value = b64ToDataView(r.data);
        return self.value;
      });
  };
  Characteristic.prototype.writeValue = function (data) {
    return send('write', {
      device: this._device.id, characteristic: this.uuid,
      data: dataToB64(data), response: true
    }).then(function () { return undefined; });
  };
  Characteristic.prototype.writeValueWithResponse = Characteristic.prototype.writeValue;
  Characteristic.prototype.writeValueWithoutResponse = function (data) {
    return send('write', {
      device: this._device.id, characteristic: this.uuid,
      data: dataToB64(data), response: false
    }).then(function () { return undefined; });
  };
  Characteristic.prototype.startNotifications = function () {
    var self = this;
    return send('notify', { device: this._device.id, characteristic: this.uuid, on: true })
      .then(function () { return self; });
  };
  Characteristic.prototype.stopNotifications = function () {
    var self = this;
    return send('notify', { device: this._device.id, characteristic: this.uuid, on: false })
      .then(function () { return self; });
  };

  function Service(device, info) {
    this.uuid = info.uuid;
    this.device = device;
    this._chars = {};
    var list = info.characteristics || [];
    for (var i = 0; i < list.length; i++) {
      this._chars[canon(list[i].uuid)] = new Characteristic(device, this, list[i]);
    }
  }
  Service.prototype.getCharacteristic = function (uuid) {
    var c = this._chars[canon(uuid)];
    if (c) return Promise.resolve(c);
    var e = new Error('No Characteristic matching UUID ' + uuid + ' found.');
    e.name = 'NotFoundError';
    return Promise.reject(e);
  };
  Service.prototype.getCharacteristics = function () {
    var self = this;
    return Promise.resolve(Object.keys(this._chars).map(function (k) { return self._chars[k]; }));
  };

  /* One object is both the GATT server and the remote-server handle, which is
     what the spec's connect() returns anyway, and it keeps `connected` in one
     place rather than two that can disagree. */
  function Gatt(device) {
    this.device = device;
    this.connected = false;
    this._services = {};
  }
  Gatt.prototype.connect = function () {
    var self = this;
    return send('connect', { device: this.device.id }).then(function (r) {
      self._services = {};
      var list = r.services || [];
      for (var i = 0; i < list.length; i++) {
        self._services[canon(list[i].uuid)] = new Service(self.device, list[i]);
      }
      self.connected = true;
      if (r.name) self.device.name = r.name;
      return self;
    });
  };
  Gatt.prototype.disconnect = function () {
    this.connected = false;
    send('disconnect', { device: this.device.id });
  };
  Gatt.prototype.getPrimaryService = function (uuid) {
    var s = this._services[canon(uuid)];
    if (s) return Promise.resolve(s);
    var e = new Error('No Services matching UUID ' + uuid + ' found.');
    e.name = 'NotFoundError';
    return Promise.reject(e);
  };
  Gatt.prototype.getPrimaryServices = function () {
    var self = this;
    return Promise.resolve(Object.keys(this._services).map(function (k) { return self._services[k]; }));
  };

  function Device(info) {
    Emitter.call(this);
    this.id = info.id;
    this.name = info.name || null;
    this.gatt = new Gatt(this);
    this._watching = false;
  }
  Device.prototype = Object.create(Emitter.prototype);
  Device.prototype.watchAdvertisements = function (opts) {
    var self = this;
    this._watching = true;
    if (opts && opts.signal) {
      opts.signal.addEventListener('abort', function () { self._watching = false; });
    }
    /* Nothing to ask the app for: it reports every advertisement it sees while a
       scan is running, and this flag is only about which devices care. */
    return send('scan', { prefixes: [], services: [] }).then(function () { return undefined; });
  };
  Device.prototype.forget = function () {
    return send('forget', { device: this.id });
  };

  function device(info) {
    var d = devices[info.id];
    if (!d) d = devices[info.id] = new Device(info);
    if (info.name) d.name = info.name;
    return d;
  }

  /* ---- navigator.bluetooth --------------------------------------------- */

  function Bluetooth() { Emitter.call(this); }
  Bluetooth.prototype = Object.create(Emitter.prototype);

  Bluetooth.prototype.getAvailability = function () { return Promise.resolve(true); };

  /* On iOS there is no per-site permission to grant, so "already permitted"
     means "this app has seen it before and the system still knows it". That is
     the same promise the page relies on: a returning pilot gets their wraps
     without a dialog. */
  Bluetooth.prototype.getDevices = function () {
    return send('known', {}).then(function (r) {
      return (r.devices || []).map(device);
    });
  };

  Bluetooth.prototype.requestDevice = function (options) {
    options = options || {};
    var f = filtersFor(options.filters);
    return send('pick', { prefixes: f.prefixes, names: f.names, services: f.services })
      .then(function (r) {
        if (!r || !r.device) {
          var e = new Error('User cancelled the requestDevice() chooser.');
          e.name = 'NotFoundError';
          throw e;
        }
        return device(r.device);
      });
  };

  Bluetooth.prototype.requestLEScan = function (options) {
    options = options || {};
    var f = filtersFor(options.filters);
    return send('scan', { prefixes: f.prefixes, names: f.names, services: f.services })
      .then(function () {
        return {
          active: true,
          keepRepeatedDevices: !!options.keepRepeatedDevices,
          stop: function () { send('scanStop', {}); }
        };
      });
  };

  function filtersFor(filters) {
    var prefixes = [], names = [], services = [];
    (filters || []).forEach(function (f) {
      if (!f) return;
      if (f.namePrefix) prefixes.push(f.namePrefix);
      if (f.name) names.push(f.name);
      (f.services || []).forEach(function (s) { services.push(canon(s)); });
    });
    return { prefixes: prefixes, names: names, services: services };
  }

  var bluetooth = new Bluetooth();
  Object.defineProperty(window.navigator, 'bluetooth', {
    value: bluetooth, configurable: true, enumerable: true
  });
  window.__impktShim = true;

  /* ---- what the app calls back into ----------------------------------- */

  window.__impkt = {
    reply: function (id, ok, payload) {
      var p = pending[id];
      if (!p) return;
      delete pending[id];
      if (ok) p.resolve(payload || {});
      else {
        var e = new Error((payload && payload.message) || 'the app refused that');
        e.name = (payload && payload.name) || 'NetworkError';
        p.reject(e);
      }
    },

    advertisement: function (info) {
      var d = device(info);
      var ev = { type: 'advertisementreceived', device: d, rssi: info.rssi,
                 name: d.name, uuids: info.uuids || [], target: d };
      bluetooth.dispatchEvent(ev);
      if (d._watching) d.dispatchEvent(ev);
    },

    notify: function (info) {
      var d = devices[info.device];
      if (!d) return;
      var keys = Object.keys(d.gatt._services);
      for (var i = 0; i < keys.length; i++) {
        var c = d.gatt._services[keys[i]]._chars[canon(info.characteristic)];
        if (!c) continue;
        c.value = b64ToDataView(info.data);
        c.dispatchEvent({ type: 'characteristicvaluechanged', target: c });
        return;
      }
    },

    disconnected: function (info) {
      var d = devices[info.device];
      if (!d) return;
      d.gatt.connected = false;
      d.dispatchEvent({ type: 'gattserverdisconnected', target: d });
    },

    /* The app's own chrome asks the page for these, so the two never disagree
       about what is connected. */
    state: function () {
      var out = [];
      Object.keys(devices).forEach(function (k) {
        out.push({ id: k, name: devices[k].name, connected: devices[k].gatt.connected });
      });
      return out;
    }
  };
}());
