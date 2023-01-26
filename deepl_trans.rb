# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

class Trans
  def initialize(key)
    @auth_key = key
  end

  def trans(msg, tgt_lng = 'JA')
    params = { auth_key: @auth_key, text: msg, target_lang: tgt_lng }
    query_params = URI.encode_www_form(params)
    uri = URI.parse("https://api-free.deepl.com/v2/translate?#{query_params}")
    res = Net::HTTP.post_form(uri, {})
    case res
    when Net::HTTPSuccess
      nil
    else
      puts "Return HTTP code: #{res.code}"
      puts res.body
      raise
    end
    begin
      json = JSON.parse(res.body, symbolize_names: true)
      json[:translations].first[:text]
    rescue StandardError
      puts 'failed translator'
      ''
      raise
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  t = Trans.new('DEEPL AUTH KEY HERE')
  puts t.trans('very rare and exclusive hat')
end
