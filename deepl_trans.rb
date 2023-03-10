# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# 親クラス：互換性維持用
class Translator
  def initialize; end

  def trans
    raise NotImplementedError
  end
end

# DeepL 翻訳用クラス
class DeeplTranslator < Translator
  PRO_API = 'https://api.deepl.com/v2/translate'
  FREE_API = 'https://api-free.deepl.com/v2/translate'

  def initialize(key, paid: true)
    super()
    @auth_key = key
    @paid = paid
  end

  private

  def build_request(msg, tgt_lng)
    params = { text: msg, target_lang: tgt_lng }
    uri = @paid ? URI.parse(PRO_API) : URI.parse(FREE_API)
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "DeepL-Auth-Key #{@auth_key}"
    req.set_form_data(params)
    [uri, req]
  end

  def check_response(response)
    case response
    when Net::HTTPSuccess
      nil
    else
      puts "Return HTTP code: #{response.code}"
      puts response.body
      raise
    end
  end

  def parser(response)
    json = JSON.parse(response.body, symbolize_names: true)
    json[:translations].first[:text]
  rescue StandardError
    puts 'Failed json parse'
    raise
  end

  public

  def trans(msg, tgt_lng = 'JA')
    raise 'Cannot trans. over 5000 characters' if msg.length >= 5000 && free

    uri, req = build_request(msg, tgt_lng)
    req_options = { use_ssl: uri.scheme == 'https' }
    res = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(req)
    end
    check_response(res)
    parser(res)
  end
end
