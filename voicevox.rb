# frozen_string_literal: true

require 'net/http'
require 'uri'

VOICEVOX_HOST = 'voicevox'
VOICEVOX_PORT = 50_021

class Voicevox
  def initialize(speaker = :metan)
    @speaker_id = case speaker
                  when :zundamon
                    1
                  when :metan
                    0
                  else
                    2
                  end
  end

  def speak(body)
    speaker_id = @speaker_id
    query_json = query(body, speaker_id)
    request_wav(query_json, speaker_id)
  end

  def self.speak(body, speaker = :metan)
    ins = new(speaker)
    ins.speak(body)
  end

  private

  def query(body, speaker_id)
    params = { text: body, speaker: speaker_id }
    query_params = URI.encode_www_form(params)
    uri = URI.parse("http://#{VOICEVOX_HOST}:#{VOICEVOX_PORT}/audio_query?#{query_params}")
    res = Net::HTTP.post_form(uri, {})
    case res
    when Net::HTTPSuccess
      nil
    else
      puts "Return HTTP code: #{res.code}"
      puts res.body
      raise
    end
    res.body
  end

  def request_wav(json, speaker_id)
    headers = { 'Content-Type' => 'application/json' }
    uri = URI.parse("http://#{VOICEVOX_HOST}:#{VOICEVOX_PORT}/synthesis?speaker=#{speaker_id}")
    req = Net::HTTP.new(uri.host, uri.port)
    res = req.post(uri.request_uri, json, headers)
    case res
    when Net::HTTPSuccess
      nil
    else
      puts "Return HTTP code: #{res.code}"
      puts res.body
      raise
    end
    res.body
  end
end

if __FILE__ == $PROGRAM_NAME
  open('/tmp/test.wav', 'wb') do |fd|
    fd.write Voicevox.speak('これはテストなのだ', :zundamon)
  end
end
