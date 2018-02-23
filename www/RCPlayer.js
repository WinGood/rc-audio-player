/*global cordova, module*/

module.exports = {
  initQueue: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'initQueue', [params]);
  },
  add: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'add', [params]);
  },
  replace: function(index, song) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'replaceTrack', [index, song]);
  },
  remove: function(index) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'removeTrack', [index]);
  },
  playTrack: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'playTrack', [params]);
  },
  pauseTrack: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'pauseTrack', [params]);
  },
  setCurrentTime: function(seconds) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'setCurrentTimeJS', [seconds]);
  },
  reset: function(successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'reset');
  },
  subscribe: function (onUpdate) {
    module.exports.updateCallback = onUpdate;
  },
  listen: function () {
    cordova.exec(module.exports.receiveCallbackFromNative, function (res) {
    }, 'RCPlayer', 'setWatcherFromJS', []);
  },
  receiveCallbackFromNative: function (messageFromNative) {
    module.exports.updateCallback(messageFromNative);
    cordova.exec(module.exports.receiveCallbackFromNative, function (res) {
    }, 'RCPlayer', 'setWatcherFromJS', []);
  }
};
