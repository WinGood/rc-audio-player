/*global cordova, module*/

module.exports = {
  initQueue: function(params) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'initQueue', [
      params
    ]);
  },
  add: function(params) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'add', [params]);
  },
  replace: function(index, song) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'replaceTrack', [
      index,
      song
    ]);
  },
  remove: function(index) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'removeTrack', [
      index
    ]);
  },
  setShuffling: function(value) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'setShuffling', [
      value
    ]);
  },
  playTrack: function(params) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'playTrack', [
      params
    ]);
  },
  pauseTrack: function(params) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'pauseTrack', [
      params
    ]);
  },
  setCurrentTime: function(seconds) {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'setCurrentTimeJS', [
      seconds
    ]);
  },
  reset: function() {
    cordova.exec(function() {}, function() {}, 'RCPlayer', 'reset');
  },
  subscribe: function(onUpdateCallback) {
    module.exports.updateCallback = onUpdateCallback;
  },
  listen: function() {
    cordova.exec(
      module.exports.receiveCallbackFromNative,
      function(res) {},
      'RCPlayer',
      'setWatcherFromJS',
      []
    );
  },
  receiveCallbackFromNative: function(messageFromNative) {
    module.exports.updateCallback(messageFromNative);
    cordova.exec(
      module.exports.receiveCallbackFromNative,
      function(res) {},
      'RCPlayer',
      'setWatcherFromJS',
      []
    );
  }
};
