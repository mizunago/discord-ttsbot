# frozen_string_literal: true

require 'bundler'
Bundler.require
require 'discordrb'
require 'aws-sdk-polly'
require 'active_support'
require 'active_support/core_ext'
require 'sqlite3'
require 'pp'
require 'tempfile'
require 'open-uri'
require_relative 'voicevox'
require_relative 'deepl_trans'

%w[DISCORD_BOT_TOKEN POLLY_VOICE_ID TTS_CHANNELS COMMAND_PREFIX].each do |require_param|
  if ENV[require_param].nil?
    puts "#{require_param} is required."
    exit(1)
  end
end

DISCORD_BOT_TOKEN = ENV['DISCORD_BOT_TOKEN']
POLLY_VOICE_ID = ENV['POLLY_VOICE_ID']
TTS_CHANNELS = ENV['TTS_CHANNELS'].split(',')
COMMAND_PREFIX = ENV['COMMAND_PREFIX']
VOICEVOX_VOICE_ID = ENV['VOICEVOX_VOICE_ID']
USE_TRANSLATOR = !ENV['DEEPL_AUTH_KEY'].nil?
DEEPL_AUTH_KEY = ENV['DEEPL_AUTH_KEY']
SRC_TRANS_CHANNELS = ENV['SRC_TRANS_CHANNELS'].split(',')
# DST_TRANS_CHANNELS = ENV['DST_TRANS_CHANNELS'].split(',')

SAMPLE_RATE = '16000'
MP3_DIR      = '/data/mp3'
NAME_DIR     = '/data/name'

def db_connect_and_create
  sqlite = SQLite3::Database.new('/data/discord.db')
  sql = <<-SQL
    create table special_word_list (
      keyword text primary key,
      url text not null default '',
      downloaded boolean not null default '0',
      path text not null default '',
      volume integer not null default '100',
      speak boolean not null default '0'
    );

    create table correct_word_list (
      keyword text primary key,
      body text not null default ''
    );

    create table name_list (
      id text primary key,
      name text not null default ''
    );
  SQL

  begin
    sqlite.execute(sql)
  rescue SQLite3::SQLException => e
    raise unless e.message.include?('already exists')
  end
  sqlite
end

class SotTime
  def initialize(time)
    @time = time
  end

  def sec
    0
  end

  def min
    @time.sec
  end

  def hour
    (@time.hour % 2).zero? ? (@time.min + 12) % 24 : @time.min % 24
  end

  def day
    correct = 0
    min_count = @time.min / 24.0
    min_count += 1
    days = @time.hour % 12 * 60 / 24.0
    ((days + min_count + correct) % 30).round
  end

  def print
    "#{@time.day}日 #{'%2.2d' % @time.hour}時 #{'%2.2d' % @time.min}分"
  end
end

class CustomBot
  def initialize(bot, db, **kwargs)
    @bot = bot
    @db = db
    @cmd_prefix = kwargs[:prefix].nil? ? '!' : kwargs[:prefix]
    @polly = Aws::Polly::Client.new
    @txt_channel = nil
  end

  def connect(event)
    channel = event.user.voice_channel
    @voice_channel = channel
    @txt_channel = event.channel

    unless channel
      event << '```'
      event << 'ボイスチャンネルに接続されていません'
      event << '```'
      return
    end

    # ボイスチャンネルにbotを接続
    @bot.voice_connect(channel)
    event << '```'
    event << "ボイスチャンネル「#{channel.name}」に接続しました。"
    event << "「#{@cmd_prefix} help」でコマンド一覧を確認できます"
    event << "「#{@cmd_prefix} chname 名前」で読み上げてもらう名前を変更することができます"
    event << 'VOICEVOX:四国めたん VOICEVOX:ずんだもん'
    event << '```'
  end

  def destroy(event)
    begin
      channel = event.user.voice_channel
    rescue StandardError
      channel = @voice_channel
    end
    server = event.server.resolve_id

    unless channel
      event << '```'
      event << 'ボイスチャンネルに接続されていません'
      event << '```'
      return
    end

    @bot.voice_destroy(server)
    event << '```'
    event << "ボイスチャンネル「 #{channel.name}」から切断されました"
    event << '```'
    @voice_channel = nil
    @txt_channel = nil
  end

  def trans(event, deepl)
    channel = event.channel
    message = event.message.to_s

    event << deepl.trans(message)
  end

  def speak(event, actor, voicevox_actor)
    return if @txt_channel.nil?

    channel   = event.channel
    server    = event.server
    message = event.message.to_s
    voice_bot = begin
      event.voice
    rescue StandardError
      nil
    end
    # ボイスチャット接続していないときは抜ける
    return if voice_bot.nil?

    # 召喚されたチャンネルと異なるテキストチャンネルは読み上げない
    return if channel.name != @txt_channel.name
    # 入力されたのがコマンド文字だったら抜ける
    return unless /^[^#{@cmd_prefix}]/ =~ message

    # `chname` で指定された名前があれば設定
    name_path = "#{NAME_DIR}/#{server.resolve_id}_#{event.user.resolve_id}"
    speaker_name = if File.exist?(name_path)
                     File.read(name_path).to_s
                   else
                     event.user.name.to_s
                   end

    message = event.message.to_s
    # メッセージ内に URL が含まれていたら読み上げない
    message = 'URL 省略' if message.include?('http://') || message.include?('https://')

    message_template = "#{speaker_name} さんの発言、#{message}"
    special_word_voice(event, message)
    # voicevox を試してだめだったら AWS Polly を使う
    begin
      raise
      path = "#{MP3_DIR}/#{server.resolve_id}_#{channel.resolve_id}_speech.wav"
      open(path, 'wb') do |fd|
        fd.write(Voicevox.speak(message_template, voicevox_actor.to_sym))
      end
      voice_bot.play_file(path)
    rescue StandardError
      # polly で作成した音声ファイルを再生
      @polly.synthesize_speech(
        {
          response_target: "#{MP3_DIR}/#{server.resolve_id}_#{channel.resolve_id}_speech.mp3",
          output_format: 'mp3',
          sample_rate: SAMPLE_RATE,
          text: "<speak>#{message_template}</speak>",
          text_type: 'ssml',
          voice_id: actor
        }
      )
      voice_bot.play_file("#{MP3_DIR}/#{server.resolve_id}_#{channel.resolve_id}_speech.mp3")
    end
  end

  def chname(event, name)
    File.open("#{NAME_DIR}/#{event.server.resolve_id}_#{event.user.resolve_id}", 'w') do |f|
      f.puts(name.to_s)
    end

    event << '```'
    event << "呼び方を#{name}に変更しました。"
    event << '```'
  end

  def special_word_voice(event, message)
    voice_bot = event.voice
    %w[船がいる 船がいます プレイヤー船 敵船].each do |word|
      voice_bot.play_file("#{MP3_DIR}/alarm.mp3") if message.include?(word)
    end
    ['ごまだれ'].each do |word|
      voice_bot.play_file("#{MP3_DIR}/gomadare.mp3") if message.include?(word)
    end
    ['ニュータイプ'].each do |word|
      voice_bot.play_file("#{MP3_DIR}/newtype.mp3") if message.include?(word)
    end
  end

  def disconnect_when_no_one(event)
    channel = event.channel
    if @voice_channel && (@voice_channel.users.size == 1 && @voice_channel.users[0].name.include?('BOT'))
      event.bot.send_message(@txt_channel, "ボイスチャンネル  #{@voice_channel.name}  から誰もいなくなったので切断します")
      destroy(event)
    end
  end
end

# DB 接続はシングルトン
db = db_connect_and_create

bot = Discordrb::Commands::CommandBot.new(token: DISCORD_BOT_TOKEN, prefix: "#{COMMAND_PREFIX} ")
bot_func = CustomBot.new(bot, db, { prefix: COMMAND_PREFIX })
deepl = Trans.new(DEEPL_AUTH_KEY)

puts "#{COMMAND_PREFIX} connect で呼んでください"

bot.command(:connect,
            description: '読み上げbotを接続中の音声チャンネルに参加させます',
            usage: "#{COMMAND_PREFIX} connect") do |event|
  bot_func.connect(event)
end

bot.command(:s,
            description: '読み上げbotを接続中の音声チャンネルに参加させます',
            usage: "#{COMMAND_PREFIX} s") do |event|
  bot_func.connect(event)
end

bot.command(:destroy,
            description: '音声チャンネルに参加している読み上げbotを切断します',
            usage: "#{COMMAND_PREFIX} destroy") do |event|
  bot_func.destroy(event)
end
bot.command(:bye,
            description: '音声チャンネルに参加している読み上げbotを切断します',
            usage: "#{COMMAND_PREFIX} bye") do |event|
  bot_func.destroy(event)
end

bot.command(:in_game_time,
            description: 'ゲーム内の時間を表示します',
            usage: "#{COMMAND_PREFIX} in_game_time") do |event|
  event << "ゲーム内は「#{SotTime.new(Time.now.utc).print}」です"
end

bot.command(:chname,
            min_args: 1, max_args: 1,
            description: 'botに読み上げられる自分の名前を設定します',
            usage: "#{COMMAND_PREFIX} chname [名前（ひらがななど）]") do |event, name|
  bot_func.chname(event, name)
end

bot.message(in: TTS_CHANNELS) do |event|
  bot_func.speak(event, POLLY_VOICE_ID, VOICEVOX_VOICE_ID)
end

bot.message(in: SRC_TRANS_CHANNELS) do |event|
  bot_func.trans(event, deepl) if USE_TRANSLATOR
end

bot.message(in: '#自動ロール付与') do |event|
  next unless COMMAND_PREFIX.include?('jack')

  message = event.message
  user = message.author
  notice = ''
  role = event.server.roles.find { |r| r.name == '乗船待機中' }
  role ||= event.server.create_role
  role.name = '乗船待機中'
  if message.to_s.include?('解除') or message.to_s.include?('下船')
    user.remove_role(role)
    notice = event.respond("おう、#{user.nick || user.username}は船を降りるのか。またな！")
  else
    user.add_role(role)
    notice = event.respond("よお新入り。お前は#{user.nick || user.username}っていうのか。乗船希望名簿に入れておくぜ")
  end
  message.delete
  sleep 10
  notice.delete
end

bot.reaction_add do |event|
  next unless COMMAND_PREFIX.include?('jack')

  # なごなごのユーザーID＆絵文字のアテナ＆特定チャンネルでのみ発動
  if event.user.id == 311_482_797_053_444_106 && event.emoji.id == 577_368_513_375_633_429 && event.channel.name == '呪われし者の酒場'
    role = event.server.roles.find { |r| r.name == '伝説の海賊' }
    message = event.message
    user = event.message.author
    message.respond("すまねえな！確認に時間がかかっちまった。#{user.nick || user.username}が「伝説の海賊」の仲間入りだってよ！盛大に飲んで祝ってやろうぜ！")
    message.create_reaction('🍺') # ビール
    message.create_reaction('🎉') # クラッカー
  end
end

bot.message do |event|
  next unless COMMAND_PREFIX.include?('jack')

  role = event.server.roles.find { |r| r.name == '乗船待機中' }
  user = event.author

  if event.channel.name.include?('船員募集-') or event.channel.name.include?('実験室')
    regex = event.message.to_s.match(/[＠@][1-9１－９]/)
    if regex
      event.message.respond("<@&#{role.id}> のみんな！ #{event.channel.name} で #{user.nick || user.username} の海賊船が船乗りを募集中だってよ！")
    end
  end
end

bot.message(in: '#呪われし者の酒場') do |event|
  next unless COMMAND_PREFIX.include?('jack')

  message = event.message
  # 画像添付をチェック
  images = message.attachments
  if images.size.zero?
    message.delete
    r = event.respond('おい、画像の添付をわすれてるようだぞ')
    sleep 10
    r.delete
    next
  end

  unless images[0].image?
    message.delete
    r = event.respond('おい、画像じゃないもんを送りつけないでくれ')
    sleep 10
    r.delete
    next
  end
  url = images[0].url
  filename = "temp#{File.extname(url)}"
  URI.open(url) do |f|
    open(filename, 'wb') do |fd|
      fd.write(f.read)
    end
  end

  # ロールの読み出し
  message = event.message
  user = message.author
  notice = ''
  role = event.server.roles.find { |r| r.name == '伝説の海賊' }
  unless role
    role = event.server.create_role
    role.name = '伝説の海賊'
  end

  # 名前がルール通りかチェック
  name = nil
  [/(?<=\().*?(?=\))/, /(?<=（).*?(?=）)/].each do |reg|
    unless user.nick.nil?
      name = user.nick.slice(reg)
      break unless name.nil?
    end
  end
  if name.nil? or name.empty?
    notice = event.respond("えーっと、お前さんの名前は・・・？\n名前は #※必読-初めて参加した方へ の通りに付けてるよな？\n俺が適当にお前の名前を付けてやってもいいんだが…")
  end

  # ローカルに画像を保存
  filename = "temp#{File.extname(url)}"
  URI.open(url) do |f|
    open(filename, 'wb') do |fd|
      fd.write(f.read)
    end
  end
  # 画像から文字を抽出
  result = system("convert -threshold 40000 #{filename} #{filename}")
  result = system("tesseract #{filename} out -l jpn")
  unless result
    notice = event.respond('すまねえがイカスミ野郎のせいで文字が読めないんだ。管理人を呼んでくれ')
    next
  end
  caption_text = ''
  open('out.txt', 'rb') do |fd|
    caption_text = fd.read.force_encoding('utf-8').encode!
  end
  puts caption_text
  puts name

  flag1 = caption_text.include?(name) unless name.nil?
  flag1 ||= caption_text.include?(user.username)
  flag1 = caption_text.include?(user.nick) if !flag1 && !user.nick.nil?
  flag2 = caption_text.include?('伝説の海賊')

  if flag1 && flag2
    user.add_role(role)
    notice = event.respond("#{user.nick || user.username}が「伝説の海賊」の仲間入りだってよ！盛大に飲んで祝ってやろうぜ！")
    message.create_reaction('🍺') # ビール
    message.create_reaction('🎉') # クラッカー
  elsif flag2
    notice = event.respond("すまねえ、スクリーンショットの名前と君のこのサーバーでの名前が一致していないようだ…。\nもし正しい画像をアップロードしたんだったら管理人に読んでもらうからちょっと待っていてくれ")
  else
    notice = event.respond("すまねえ、俺には読めない文字で書かれているようだ。\n背景がゴチャゴチャしていると、読みづれぇんだ。\nもし正しい画像をアップロードしたんだったら管理人に読んでもらうからちょっと待っていてくれ")
  end
end

bot.voice_state_update do |event|
  bot_func.disconnect_when_no_one(event)
end

bot.run
