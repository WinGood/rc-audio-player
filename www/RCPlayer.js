/*global cordova, module*/

module.exports = {
  initQueue: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'initQueue', [params]);
  },
  add: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'add', [params]);
  },
  replace: function(index, song) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'replaceSong', [index, song]);
  },
  remove: function(start, end, song) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'remove', [start, end, song]);
  },
  playTrack: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'playTrack', [params]);
  },
  pauseTrack: function(params, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'RCPlayer', 'pauseTrack', [params]);
  },
  setLoop: function(flag) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'setLoopJS', [flag]);
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
