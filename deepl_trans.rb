# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'net/http'

class Trans
  def initialize(key, paid = true)
    @auth_key = key
    @paid = paid
  end

  def trans(msg, tgt_lng = 'JA')
    raise 'Cannot trans. over 5000 characters' if msg.length >= 5000 && free

    params = { text: msg, target_lang: tgt_lng }
    uri = if @paid
            URI.parse("https://api.deepl.com/v2/translate")
          else
            URI.parse("https://api-free.deepl.com/v2/translate")
          end
    req_options = {
      use_ssl: uri.scheme == "https"
    }
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "DeepL-Auth-Key #{@auth_key}"
    req.set_form_data(params)

    res = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(req)
    end
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
