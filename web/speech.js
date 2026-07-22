// Web Speech API 语音识别封装
window.AiLifeSpeech = {
  recognition: null,
  finalTranscript: '',
  isRunning: false,

  start: function(lang, onResult, onError, onEnd) {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      onError('浏览器不支持语音识别，请使用 Chrome 浏览器');
      return;
    }

    this.stop();
    this.finalTranscript = '';
    this.isRunning = true;

    const recognition = new SpeechRecognition();
    recognition.lang = lang || 'zh-CN';
    recognition.continuous = true;
    recognition.interimResults = true;

    const self = this;
    this.recognition = recognition;

    recognition.onresult = function(event) {
      let interimTranscript = '';
      for (let i = event.resultIndex; i < event.results.length; i++) {
        if (event.results[i].isFinal) {
          self.finalTranscript += event.results[i][0].transcript;
        } else {
          interimTranscript += event.results[i][0].transcript;
        }
      }
      onResult(self.finalTranscript, interimTranscript);
    };

    recognition.onerror = function(event) {
      self.isRunning = false;
      onError(event.error || '语音识别错误');
    };

    recognition.onend = function() {
      self.isRunning = false;
      onEnd(self.finalTranscript);
    };

    recognition.start();
  },

  stop: function() {
    if (this.recognition) {
      this.isRunning = false;
      try { this.recognition.stop(); } catch(e) {}
      this.recognition = null;
    }
  },

  isSupported: function() {
    return !!(window.SpeechRecognition || window.webkitSpeechRecognition);
  }
};
