/*global cordova, module*/

module.exports = {
  initSong: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'Hello', 'initSong', [params]);
  },
  play: function(successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'Hello', 'play');
  },
  pause: function(successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'Hello', 'pause');
  },
  subscribe: function (onUpdate) {
    module.exports.updateCallback = onUpdate;
  },
  listen: function () {
    cordova.exec(module.exports.receiveCallbackFromNative, function (res) {
    }, 'Hello', 'watch', []);
  },
  receiveCallbackFromNative: function (messageFromNative) {
    module.exports.updateCallback(messageFromNative);
    cordova.exec(module.exports.receiveCallbackFromNative, function (res) {
    }, 'Hello', 'watch', []);
  }
};
