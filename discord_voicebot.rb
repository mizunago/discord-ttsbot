# frozen_string_literal: true

require 'bundler'
Bundler.require
require 'digest'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'google/apis/calendar_v3'
require 'google/cloud/vision'
require 'discordrb'
require 'aws-sdk-polly'
require 'active_support'
require 'active_support/core_ext'
require 'simple_twitter'
require 'sqlite3'
require 'yaml'
require 'tempfile'
require 'open-uri'
require 'rufus-scheduler'
require 'twitch-api'
require 'net/http'
require 'uri'
require 'logger'
require_relative 'voicevox'
require_relative 'deepl_trans'

%w[DISCORD_BOT_TOKEN POLLY_VOICE_ID COMMAND_PREFIX].each do |require_param|
  if ENV[require_param].nil?
    puts "#{require_param} is required."
    exit(1)
  end
end

DISCORD_BOT_TOKEN = ENV['DISCORD_BOT_TOKEN']
POLLY_VOICE_ID = ENV['POLLY_VOICE_ID']
COMMAND_PREFIX = ENV['COMMAND_PREFIX']
VOICEVOX_VOICE_ID = ENV['VOICEVOX_VOICE_ID']
USE_TRANSLATOR = !ENV['DEEPL_AUTH_KEY'].nil?
DEEPL_AUTH_KEY = ENV['DEEPL_AUTH_KEY']
DEEPL_PRO = ENV['DEEPL_PRO'].nil? ? false : ENV['DEEPL_PRO'].downcase == 'true'
SRC_TRANS_CHANNELS = ENV['SRC_TRANS_CHANNELS'].split(',')
# DST_TRANS_CHANNELS = ENV['DST_TRANS_CHANNELS'].split(',')
ENV['VISION_CREDENTIALS'] = 'vision.json'

SAMPLE_RATE = '16000'
MP3_DIR      = '/data/mp3'
NAME_DIR     = '/data/name'

EMOJI_A = '🇦'
EMOJI_B = '🇧'
EMOJI_C = '🇨'
EMOJI_D = '🇩'
EMOJI_E = '🇪'
EMOJI_2 = '2️⃣'
EMOJI_3 = '3️⃣'
EMOJI_4 = '4️⃣'
EMOJI_POINT_UP = '☝️'
EMOJI_SIME = '✅'
EMOJI_BEER = '🍺'
EMOJI_PARTY_POPPER = '🎉'
EMOJI_HAND = '✋'
EMOJI_GOLD_HOARDERS = 'Gold_Hoarders'
EMOJI_MERCHANT_ALLIANCE = 'Merchant_Alliance'
EMOJI_ORDER_OF_SOULS = 'Order_of_Souls'
EMOJI_ATHENAS_FORTUNE = 'Athenas_Fortune'
EMOJI_REAPERS_BONES = 'Reapers_Bones'
EMOJI_BILGE_RAT = 'Bilge_Rat'
EMOJI_HUNTERS_CALL = 'Hunters_Call'
EMOJI_HUNTRESS_FLAG = 'Huntress_Flag'
EMOJI_PC = '🖥️'
EMOJI_XBOX = 'Xbox'
EMOJI_XBOX_GAME_PASS = 'XboxGamePass'
EMOJI_STEAM = 'Steam'
EMOJI_MICROSOFT_STORE = 'Microsoft_Store'
EMOJI_PS = 'PlayStation'
EMOJI_CONTROLLER = '🎮'
EMOJI_KEYBOARD = '⌨'
EMOJI_SMARTPHONE = '📱'
EMOJI_MICMUTE = '🔇'
EMOJI_BIGINNER = '🔰'

def group_div(user_num, number_of_member)
  sub_num = 0
  return sub_num if (user_num % (number_of_member - 1)).zero?

  loop do
    user_num -= number_of_member
    sub_num += 1
    break if (user_num % (number_of_member - 1)).zero?
  end
  sub_num
end

def emoji_name(event)
  case event.emoji.name
  when EMOJI_HAND
    '乗船待機中'
  when EMOJI_GOLD_HOARDERS
    'ゴールド・ホーダー'
  when EMOJI_MERCHANT_ALLIANCE
    'マーチャント・アライアンス'
  when EMOJI_ORDER_OF_SOULS
    'オーダー・オブ・ソウル'
  when EMOJI_ATHENAS_FORTUNE
    'アテナ・フォーチュン'
  when EMOJI_REAPERS_BONES
    'リーパーズ・ボーン'
  when EMOJI_BILGE_RAT
    'ビルジ・ラット'
  when EMOJI_HUNTERS_CALL
    'ハンターズ・コール'
  when EMOJI_HUNTRESS_FLAG
    'イベントハンター'
  when EMOJI_PC
    'PC'
  when EMOJI_XBOX
    'Xbox'
  when EMOJI_XBOX_GAME_PASS
    'Xboxゲームパス'
  when EMOJI_STEAM
    'Steam'
  when EMOJI_MICROSOFT_STORE
    'Microsoft Store'
  when EMOJI_PS
    'PlayStation'
  when EMOJI_CONTROLLER
    'コントローラー'
  when EMOJI_KEYBOARD
    'キーボード＆マウス'
  when EMOJI_SMARTPHONE
    'タッチ操作'
  when EMOJI_MICMUTE
    'マイクミュート'
  when EMOJI_BIGINNER
    '初心者'
  end
end

def db_connect_and_create
  file_name = '/data/discord.db'
  # File.delete(file_name) if File.exist?(file_name)
  sqlite = SQLite3::Database.new(file_name)
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

    create table registered_events (
      id text primary key,
      name text not null default ''
    );

    create table last_twitch_crawler_times (
      id integer primary key
    );

    create table last_twitter_crawler_times (
      name text primary key,
      id integer not null default '0'
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
    @time = Time.at(time.to_i).utc
  end

  def sec
    0
  end

  def min
    @time.sec
  end

  def hour
    (@time.hour % 2).zero? ? @time.min % 24 : (@time.min + 12) % 24
  end

  def day
    (@time.to_i / (24 * 60) % 30 + 1).round
  end

  def print
    "#{day}日 #{'%2.2d' % hour}時 #{'%2.2d' % min}分"
  end
end

class BPTime
  def initialize(init_time = nil, diff = 5.minutes)
    @diff = diff
    @init_time = init_time
  end

  def time
    @init_time ? (@init_time + @diff).to_i : (Time.new.utc + @diff).to_i
  end

  def min
    time / 60 % 60
  end

  def min_num
    time / 60 / 25
  end

  def sec
    time % 60
  end

  def night?
    min_num.even?
  end

  def noon?
    min_num.odd?
  end

  def hour
    time / 60 % 25
  end

  def time_left
    26 - hour
  end

  def to_daytime
    noon? ? '昼' : '夜'
  end

  def now
    if noon?
      (7 + (hour / 25.0) * 12).floor
    else
      t_hour = (18 + (hour / 25.0) * 12).floor
      t_hour -= 24 if t_hour >= 24
      t_hour
    end
  end

  def print
    ''"現在は「#{to_daytime}」です
ゲーム内時刻は大体 #{now}時くらい
残り#{time_left}分で昼夜が変わるよ
    "''
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
    # ボイスチャット接続不具合で停止されると困るので動作させない
    return

    channel = event.user.voice_channel
    @voice_channel = channel
    @txt_channel = event.channel

    unless channel
      @txt_channel.send_message('ボイスチャンネルに接続されていません')
      return
    end

    # ユーザー数制限のあるチャンネルには接続しない
    unless @voice_channel.user_limit.zero?
      @txt_channel.send_message('人数制限のあるチャンネルにはBOTを呼ぶことはできません「人数無制限」の船で呼んでください')
      return
    end

    # ボイスチャンネルにbotを接続
    @bot.voice_connect(channel)
    @txt_channel.send_message("ボイスチャンネル「#{channel.name}」に接続しました。")
  end

  def destroy(event)
    # ボイスチャット接続不具合で停止されると困るので動作させない
    return

    begin
      channel = event.user.voice_channel
    rescue StandardError
      channel = @voice_channel
    end
    server = event.server.resolve_id

    unless channel
      @txt_channel.send_message('ボイスチャンネルに接続されていません')
      return
    end

    @bot.voice_destroy(server)
    @txt_channel.send_message("ボイスチャンネル「 #{channel.name}」から切断されました")
    @voice_channel = nil
    @txt_channel = nil
  end

  def trans(event, deepl)
    channel = event.channel
    message = event.message.to_s

    event << deepl.trans(message)
  end

  def speak(event, actor, voicevox_actor)
    # ボイスチャット接続不具合で停止されると困るので動作させない
    return

    return if @txt_channel.nil?

    channel   = event.channel
    server    = event.server
    message = event.message.to_s
    user = event.user
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

    message_template = if user.id == @last_user&.id
                         message
                       else
                         "#{speaker_name} さんの発言、#{message}"
                       end
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
    # 最後に読み上げた人を記録
    @last_user = event.user
  end

  def chname(event, name)
    File.open("#{NAME_DIR}/#{event.server.resolve_id}_#{event.user.resolve_id}", 'w') do |f|
      f.puts(name.to_s)
    end
    event.channel.send_message("呼び方を#{name}に変更しました。")
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

  def connect_when_create_command(event)
    return unless COMMAND_PREFIX.include?('jack')

    channel = event.channel
    return unless channel

    name = channel.name
    return unless channel.name
    return unless name.include?('作成')

    size = nil
    ship_type = ''
    if name.include?('ガレオン')
      ship_type = 'ガレオン'
      size = 4
    elsif name.include?('ブリガンティン')
      ship_type = 'ブリガンティン'
      size = 3
    elsif name.include?('スループ')
      ship_type = 'スループ'
      size = 2
    elsif name.include?('人数無制限')
      ship_type = '人数無制限'
      size = nil
    end
    server = event.server

    # チャンネル作成
    categories = event.server.categories.select { |ch| ch.name.include?(ship_type) }
    room_number = categories.size + 1
    cr_ch = server.create_channel("#{ship_type}##{format('%02d', room_number)}", :category)
    voice = server.create_channel("#{ship_type}##{format('%02d', room_number)}", :voice, user_limit: size,
                                                                                         parent: cr_ch)
    # カテゴリに親カテゴリの権限とおなじものをセット
    # cr_ch.permission_overwrites = channel.category.permission_overwrites

    # チャンネルに親カテゴリの権限と同じものをセット
    # voice.permission_overwrites = channel.category.permission_overwrites

    # 順番を自動作成カテゴリの下に配置する
    role_only = server.categories.find { |ch| ch.name.include?('自動作成') }
    cr_ch.sort_after(role_only)

    # 作った人をそのチャンネルに放り込む
    server.move(event.user, voice)
  end

  def disconnect_when_no_one(event)
    sleep 5
    server = event.server
    channel = event.channel
    if @voice_channel && (@voice_channel.users.size == 1 && @voice_channel.users[0].name.include?('BOT'))
      # event.bot.send_message(@txt_channel, "ボイスチャンネル  #{@voice_channel.name}  から誰もいなくなったので切断します")
      destroy(event)
    end

    return unless COMMAND_PREFIX.include?('jack')

    # 船名の入ったカテゴリを探す
    chs = server.categories.select do |ch|
      name = ch.name
      name.include?('ガレオン') or name.include?('ブリガン') or name.include?('スループ') or name.include?('人数無制限')
    end

    # 不要になったチャンネルを削除する
    chs.each do |channel|
      # 作成から１分以上経っているか
      next unless Time.now > channel.creation_time + 3.seconds

      delete_flag = false
      channel.voice_channels.each do |voice_ch|
        delete_flag = true if voice_ch.users.size.zero?
      end
      next unless delete_flag

      channel.children.each do |child_ch|
        child_ch.delete
      rescue Discordrb::Errors::UnknownChannel
        nil
      end
      begin
        channel.delete
      rescue StandardError
        nil
      end
    end
  end

  def collect_member(event)
    org = event.message
    r = event.respond(
      "メンバーリストを作成します。希望するグループをエモートで反応してください\n" +
      "また、誰か1グループの最大人数を数字で反応してください（#{EMOJI_2}: スループ、#{EMOJI_3}: ブリガンティン, #{EMOJI_4}: ガレオン）\n" +
      "完了したら#{EMOJI_SIME}でリアクションしてください\n" +
      '※注意：グループ希望は1人1つまでにしてください(重複投票チェックはしていません) このメッセージは90秒後に消えます'
    )
    org.create_reaction(EMOJI_A)
    org.create_reaction(EMOJI_B)
    org.create_reaction(EMOJI_C)
    org.create_reaction(EMOJI_D)
    org.create_reaction(EMOJI_E)
    org.create_reaction(EMOJI_2)
    org.create_reaction(EMOJI_3)
    org.create_reaction(EMOJI_4)
    org.create_reaction(EMOJI_POINT_UP)
    org.create_reaction(EMOJI_SIME)
    sleep 90
    r.delete
  end

  def allocate_member(event)
    message = event.message
    author = event.message.author
    r = event.respond(
      "今リアクションの付いているメンバーでメンバーリストを作成します\n" +
      "再作成するには、決定リアクションを付け直してください\n" +
      "端数が出る場合にはできるだけ過半数の船になるように割り振ります。\n" +
      'もし船の数がオーバーする場合はリアクションを移動して対応してください'
    )
    # １船あたりの最大人数を取得
    number_of_member = 4
    emoji_map = [EMOJI_2, EMOJI_3, EMOJI_4]
    emoji_count = []
    emoji_map.each_with_index do |emoji, num|
      emoji_count[num] = message.reacted_with(emoji).size
    end
    number_of_member = case emoji_count.index(emoji_count.max)
                       when 0
                         2
                       when 1
                         3
                       when 2
                         4
                       else
                         raise
                       end

    emoji_map = {
      EMOJI_A.to_s => [],
      EMOJI_B.to_s => [],
      EMOJI_C.to_s => [],
      EMOJI_D.to_s => [],
      EMOJI_E.to_s => []
    }
    emoji_map.keys.each do |key|
      emoji_map[key] = message.reacted_with(key).reject { |u| u.current_bot? }
    end

    groups = {}
    group_num = 0
    team_names = ('A'..'Z').to_a.map { |alphabet| "#{alphabet}チーム" }

    emoji_map.each do |_key, users|
      if (users.size % number_of_member).zero?
        # event.message.respond("メンバー数が定員ちょうどです")
        users.shuffle.each_slice(number_of_member) do |members|
          groups[group_num] = members
          group_num += 1
        end
      elsif (users.size % number_of_member) > number_of_member / 2
        # 余りの人数が過半数を超える場合は１人欠けチームがいることを許容する
        # event.message.respond("余りの人数が過半数を超える場合は１人欠けチームを作ります")
        users.shuffle.each_slice(number_of_member) do |members|
          groups[group_num] = members
          group_num += 1
        end
      else
        # 余りの人数が過半数を超えない場合
        # event.message.respond("余りの人数が過半数を超えないので、最大人数グループといくつかの一人欠けグループを作ります")
        group_div(users.size, number_of_member).times do
          # 最大人数のグループを作る
          groups[group_num] = users.pop(number_of_member)
          group_num += 1
        end
        # 一人欠けグループを作る
        users.shuffle.each_slice(number_of_member - 1) do |members|
          groups[group_num] = members
          group_num += 1
        end
      end
    end

    team_results = groups.map do |num, members|
      members = members.map do |m|
        "<@!#{m.id}> さん"
      end
      "#{team_names[num]}: #{members.join('、　')}"
    end
    user = event.user
    event.message.respond(
      "----- チームの編成です(#{user.nick || user.username} さんが実行しました)-----\n" +
      team_results.join("\n") +
      "\n--------\n" +
      "※再編成したい場合は#{EMOJI_SIME}リアクションを付け直してください"
    )
    sleep 60
    r.delete
  end
end

file = File.open('error.log', File::WRONLY | File::APPEND | File::CREAT)
logger = Logger.new(file, 'daily', datetime_format: '%Y-%m-%d %H:%M:%S')

# DB 接続はシングルトン
db = db_connect_and_create

bot = Discordrb::Commands::CommandBot.new(token: DISCORD_BOT_TOKEN, prefix: "#{COMMAND_PREFIX} ")
bot_func = CustomBot.new(bot, db, **{ prefix: COMMAND_PREFIX })
deepl = DeeplTranslator.new(DEEPL_AUTH_KEY, paid: DEEPL_PRO)

puts "#{COMMAND_PREFIX} connect で呼んでください"

bot.register_application_command(:ping, 'BOT が生きていれば返事をします') do |cmd|
  cmd.string('message', '送信されたメッセージをオウムがえしします')
end

bot.application_command(:ping) do |event|
  event.respond(content: "pong: #{event.options['message']}")
end

bot.register_application_command(:connect, '読み上げbotを接続中の音声チャンネルに参加させます') do |cmd|
end

bot.application_command(:connect) do |event|
  bot_func.connect(event)
end

bot.register_application_command(:disconnect, '音声チャンネルに参加している読み上げbotを切断します') do |cmd|
end

bot.application_command(:disconnect) do |event|
  bot_func.destroy(event)
end

bot.register_application_command(:in_game_time, 'ゲーム内の時間を表示します') do |cmd|
end

bot.application_command(:in_game_time) do |event|
  event.respond("現在時刻は「#{Time.now.in_time_zone('Asia/Tokyo')}」です\nゲーム内は「#{SotTime.new(Time.now.utc).print}」です")
end

bot.register_application_command(:chname, 'botに読み上げられる自分の名前を設定します') do |cmd|
  cmd.string('name', '読み上げてほしい名前を書きます', required: true)
end

bot.application_command(:chname) do |event|
  bot_func.chname(event, event.options['name'] || 'ななしさん')
end

bot.command(:connect,
            description: '読み上げbotを接続中の音声チャンネルに参加させます',
            usage: "#{COMMAND_PREFIX} connect") do |event|
  bot_func.connect(event)
end

bot.command(:destroy,
            description: '音声チャンネルに参加している読み上げbotを切断します',
            usage: "#{COMMAND_PREFIX} destroy") do |event|
  bot_func.destroy(event)
end

bot.command(:in_game_time,
            description: 'ゲーム内の時間を表示します',
            usage: "#{COMMAND_PREFIX} in_game_time") do |event|
  if event.server.name.include?('Sea of Thieves JPN')
    event << "現在時刻は「#{Time.now.in_time_zone('Asia/Tokyo')}」です"
    event << "ゲーム内は「#{SotTime.new(Time.now.utc).print}」です"
  end
  if event.server.name.include?('ブルプロ')
    event << "現在時刻は「#{Time.now.in_time_zone('Asia/Tokyo')}」です"
    event << "#{BPTime.new(Time.now).print}"
  end
end

bot.command(:chname,
            min_args: 1, max_args: 1,
            description: 'botに読み上げられる自分の名前を設定します',
            usage: "#{COMMAND_PREFIX} chname [名前（ひらがななど）]") do |event, name|
  bot_func.chname(event, name)
end

bot.message do |event|
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
  role = event.server.roles.find { |r| r.name.include?('乗船待機中') }
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

  # 同鯖のメンバー割り振り機能
  if event.channel.name.include?('同鯖メンバー表') or event.channel.name.include?('実験室')
    if event.emoji.name == EMOJI_POINT_UP && !event.user.current_bot?
      bot_func.collect_member(event)
      next
    elsif event.emoji.name == EMOJI_SIME && !event.user.current_bot?
      bot_func.allocate_member(event)
      next
    end
  end

  # なごなごのユーザーID＆絵文字のアテナ＆特定チャンネルでのみ発動
  # 伝説の海賊の手動認定処理
  if event.user.id == 311_482_797_053_444_106 && event.emoji.id == 577_368_513_375_633_429 && event.channel.name.include?('呪われし者の酒場')
    role = event.server.roles.find { |r| r.name.include?('伝説の海賊') }
    user = event.message.author
    user.add_role(role)
    message = event.message
    message.respond("すまねえな！確認に時間がかかっちまった。#{user.nick || user.username} (<@!#{user.id}>)が「伝説の海賊」の仲間入りだってよ！盛大に飲んで祝ってやろうぜ！")
    message.create_reaction('🍺') # ビール
    message.create_reaction('🎉') # クラッカー
  end

  # ロール付与
  if event.channel.name.include?('自動ロール付与') or event.channel.name.include?('実験室')
    user = event.user
    role = event.server.roles.find { |r| r.name == emoji_name(event) }
    next unless role

    begin
      user.add_role(role)
    rescue StandardError
      nil
    end
  end

  # ロール付与（ルール同意）
  if event.channel.name.include?('必読')
    user = event.user
    role = event.server.roles.find { |r| r.name.include?('サーバールール同意済み') }
    next unless role

    begin
      user.add_role(role)
    rescue StandardError
      nil
    end
  end
end

bot.reaction_remove do |event|
  # ロール解除
  if event.channel.name.include?('自動ロール付与') or event.channel.name.include?('実験室')
    user = event.user
    role = event.server.roles.find { |r| r.name == emoji_name(event) }
    next unless role

    begin
      user.remove_role(role)
    rescue StandardError
      nil
    end
  end
  # ロール付与（ルール同意）
  if event.channel.name.include?('必読')
    user = event.user
    role = event.server.roles.find { |r| r.name.include?('サーバールール同意済み') }
    next unless role

    begin
      user.remove_role(role)
    rescue StandardError
      nil
    end
  end
end

bot.message do |event|
  next unless COMMAND_PREFIX.include?('jack')

  role = event.server.roles.find { |r| r.name.include?('乗船待機中') }
  user = event.author

  if event.channel.name.include?('船員募集') or event.channel.name.include?('実験室')
    regex = /([＠@(あと)]+[1-9１-９]+[人名]*)募集/
    matched = event.message.to_s.match(regex)
    if matched
      event.message.respond("<@&#{role.id}> のみんな！ <##{event.channel.id}> で #{user.nick || user.username} の海賊船が船乗りを募集中だってよ！")
    end
    regex = /(募集.*[＠@(あと)]+[1-9１-９]+[人名]*)/
    matched = event.message.to_s.match(regex)
    if matched
      event.message.respond("<@&#{role.id}> のみんな！ <##{event.channel.id}> で #{user.nick || user.username} の海賊船が船乗りを募集中だってよ！")
    end
  end
end

bot.message(in: '#🍺呪われし者の酒場') do |event|
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
  role = event.server.roles.find { |r| r.name.include?('伝説の海賊') }
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
    ch = event.server.text_channels.find { |ch| ch.name.include?('必読') }
    notice = event.respond("えーっと、お前さんの名前は・・・？\n名前は <##{ch.id}>の通りに付けてるよな？\n俺が適当にお前の名前を付けてやってもいいんだが…")
  end

  # ローカルに画像を保存
  filename = "temp#{File.extname(url)}"
  URI.open(url) do |f|
    open(filename, 'wb') do |fd|
      fd.write(f.read)
    end
  end
  # 画像から文字を抽出
  image_annotator = Google::Cloud::Vision.image_annotator
  response = image_annotator.text_detection(
    image: filename,
    max_results: 1
  )

  caption_text = ''
  response.responses.each do |res|
    caption_text = res.text_annotations[0]['description']
  end

  flag1 = caption_text.include?(name) unless name.nil?
  flag1 ||= caption_text.include?(user.username)
  flag1 = caption_text.include?(user.nick) if !flag1 && !user.nick.nil?
  flag2 = caption_text.include?('伝説の海賊')

  if flag1 && flag2
    user.add_role(role)
    notice = event.respond("#{user.nick || user.username} (<@!#{user.id}>)が「伝説の海賊」の仲間入りだってよ！盛大に飲んで祝ってやろうぜ！")
    message.create_reaction(EMOJI_BEER) # ビール
    message.create_reaction(EMOJI_PARTY_POPPER) # クラッカー
  elsif flag2
    notice = event.respond("すまねえ、スクリーンショットの名前と君のこのサーバーでの名前が一致していないようだ…。\nもし正しい画像をアップロードしたんだったら管理人に読んでもらうからちょっと待っていてくれ")
  else
    notice = event.respond("すまねえ、俺には読めなかった。\nイカスミ野郎のせいだと思うんだ\nもし正しい画像をアップロードしたんだったら管理人に読んでもらうからちょっと待っていてくれ")
  end
end

bot.voice_state_update do |event|
  bot_func.connect_when_create_command(event)
  bot_func.disconnect_when_no_one(event)
end

bot.run :async
# bot.run
s = bot.servers[406_456_641_593_016_320]

scheduler = Rufus::Scheduler.new

# 公式Twitter を翻訳して流す
scheduler.cron '2,12,22,32,42,52 * * * *' do
  next # Twitter から取得できなくなったので処理しない

  next unless COMMAND_PREFIX.include?('jack')

  config = YAML.load(File.open('twitter_secret.yml')).with_indifferent_access
  client = SimpleTwitter::Client.new(
    api_key: config[:api_key],
    api_secret_key: config[:api_secret_key],
    access_token: config[:access_token],
    access_token_secret: config[:access_token_secret]
  )

  select_sql = 'SELECT id, name FROM last_twitter_crawler_times WHERE name = ? ORDER BY id DESC LIMIT 1'
  twitter_discord_map = [
    {
      name: 'DisneyDLV',
      server_name: 'ディズニードリームライトバレー',
      ch_name: '公式ニュース'
    },
    {
      name: 'SoT_Support',
      server_name: 'Sea of Thieves JPN',
      ch_name: '公式-twitter'
    },
    {
      name: 'SeaOfThieves',
      server_name: 'Sea of Thieves JPN',
      ch_name: '公式-twitter'
    },
    {
      name: 'skullnbonesgame',
      server_name: 'Skull and Bones Japan',
      ch_name: '公式news'
    }
  ]
  twitter_discord_map.each do |account|
    user_name = account[:name]
    results = db.execute(select_sql, user_name)
    last_id = 0
    results.each do |row|
      last_id = row[0].to_i
    end
    base_time = Time.now

    server_id, server = bot.servers.find { |_id, server| server.name.include?(account[:server_name]) }
    next if s.text_channels.nil?

    ch = server.text_channels.find { |c| c.name.include?(account[:ch_name]) }

    user = client.get("https://api.twitter.com/2/users/by?usernames=#{user_name}&user.fields=created_at,profile_image_url&expansions=pinned_tweet_id&tweet.fields=author_id,created_at")
    twtter_id = user[:data][0][:id]
    request_url = "https://api.twitter.com/2/users/#{twtter_id}/tweets?exclude=replies&expansions=attachments.poll_ids,attachments.media_keys&media.fields=url&tweet.fields=created_at"
    request_url += "&since_id=#{last_id}" if last_id.positive?
    tweets = client.get(request_url)

    tweets[:data]&.reverse&.each do |tweet|
      url = "https://twitter.com/#{user_name}/status/#{tweet[:id]}"
      if tweet[:attachments]
        media_keys = tweet[:attachments][:media_keys]
        medias = tweets[:includes][:media].select do |media|
          media_keys&.include?(media[:media_key])
        end
      else
        medias = nil
      end
      begin
        ch.send_embed do |embed|
          embed.title = "@#{user_name} #{url}"
          embed.url = url
          embed.description = "訳文：

#{deepl.trans(tweet[:text])}

原文：

#{tweet[:text]}"
          embed.color = '#0000EE'
          embed.footer = { text: Time.parse(tweet[:created_at]).localtime.to_s,
                           icon_url: user[:data][0][:profile_image_url] }
          if medias && medias.dig(0, :type) == 'photo'
            embed.image = Discordrb::Webhooks::EmbedImage.new(url: medias[0][:url])
          end
        end
        if medias
          if medias.find { |m| m[:type] == 'video' }
            ch.send_message("ツイートに動画が含まれていました: #{url}")
          else
            unsent_images = medias[1..]
            ch.send_message(unsent_images.map { |m| m[:url] }.join("\n")) if unsent_images && !unsent_images.empty?
          end
        end
        next unless tweets[:meta][:result_count].positive?

        last_id = tweets[:meta][:newest_id]
        db.execute('DELETE FROM last_twitter_crawler_times WHERE name = ?', user_name)
        insert_sql = 'INSERT INTO last_twitter_crawler_times (name, id) VALUES(?, ?)'
        db.execute(insert_sql, user_name, last_id)
      rescue StandardError => e
        pp server
        pp ch
        raise
      end

      # ch.send_message("#{Time.now.iso8601} ツイート: #{url}")
    end
  end
end

# Youtube, Twitch の配信情報を流す
scheduler.cron '12, 42 * * * *' do
  next unless COMMAND_PREFIX.include?('jack')

  config = YAML.load(File.open('twitch_secret.yml')).with_indifferent_access

  tokens = TwitchOAuth2::Tokens.new(
    client: {
      client_id: config[:client_id],
      client_secret: config[:client_secret]
    }
  )

  client = Twitch::Client.new(tokens: tokens)

  next if s.text_channels.nil?

  ch = s.text_channels.find { |c| c.name.include?('配信情報') }

  # pp client.get_games(name: 'Sea of Thieves').data
  base_time = Time.now

  select_sql = 'SELECT id FROM last_twitch_crawler_times ORDER BY id DESC LIMIT 1'
  results = db.execute(select_sql)
  last_checked_time = Time.at(0)
  results.each do |row|
    last_checked_time = Time.at(row[0].to_i)
  end

  blacklists = %w[simonshisha32k army_smiley porio_m happy_ajay]
  failed = false

  begin
    game_name = 'Sea of Thieves'
    game_id = client.get_games({ name: game_name }).data&.first&.id.to_i
    client.get_streams(game_id: game_id, language: 'ja').data.each do |stream|
      user_login = stream.instance_variable_get(:@user_login)
      # 前回チェックから現在までに始まった配信でなければ無視する
      next unless (last_checked_time..base_time).cover?(stream.started_at)
      next if blacklists.include?(user_login)

      histories = ch.history(10)
      recent_streams = histories&.select do |m|
        # 直近で同じ人の配信を書き込んでいたら再度書かない
        m.text.include?("https://twitch.tv/#{user_login}") && m.timestamp + 8.hours > base_time
      end

      # 何故か別のゲームの配信を取ってきてしまうことがあるので念のため確認
      next unless stream.game_name.include?(game_name)

      # もし日本語が入ってなかったら無視する
      regex = /(?:\p{Hiragana}|\p{Katakana}|[一-龠々])/
      title_matched = stream.title.match(regex)
      # 日本語を含まない配信は除外
      next unless title_matched

      next unless recent_streams.empty?

      message = "#{stream.user_name}さんの #{stream.game_name} 配信が始まりました
  配信名： #{stream.title}
  URL: https://twitch.tv/#{user_login}

※コメント等で過剰なコーチングをしないでください（配信主が求めた以上の情報を書き込まないでください）
ガイド禁止・ネタバレ禁止などの配信主のチャットルールを守り、視聴・コメントしてください
改善されない場合は、こちらの配信情報の通知を停止します
参加型配信でない可能性があります。
"
      ch.send_message(message)
    end
  rescue StandardError => e
    failed = true
    puts e.backtrace
    logger.fatal(e.backtrace)
  end

  config = YAML.load(File.open('youtube_secret.yml')).with_indifferent_access
  query = {
    key: config[:key],
    part: 'snippet',
    type: 'video',
    eventType: 'live',
    regionCode: 'JP',
    order: 'date',
    maxResults: '8',
    q: 'Sea of Thieves'
    # maxResults: '4',
    # q: 'Dead by Daylight',
  }

  begin
    uri = URI.parse('https://www.googleapis.com/youtube/v3/search')
    uri.query = URI.encode_www_form(query)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(req)
    body = begin
      JSON.parse(res.body).with_indifferent_access
    rescue StandardError => e
      raise
    end
    # デバッグ
    puts "https://www.googleapis.com/#{uri.request_uri}"

    next if body[:items].nil?

    body[:items].each do |stream|
      url = "https://www.youtube.com/watch?v=#{stream[:id][:videoId]}"
      snippet = stream[:snippet]
      title = snippet[:title]
      description = snippet[:description]
      channelTitle = snippet[:channelTitle]
      query2 = {
        key: config[:key],
        part: 'liveStreamingDetails',
        id: stream[:id][:videoId]
      }

      # タイトルと概要欄に日本語が含まれているか？
      # regex = /(?:\p{Hiragana}|\p{Katakana}|[一-龠々])/
      regex = /(?:\p{Hiragana}+|\p{Katakana}+)/
      title_matched = title.match(regex)
      description_matched = description.match(regex)
      # 日本語を含まない配信は除外
      next unless title_matched || description_matched
      # 日本語が３文字以上なければ除外
      next unless title_matched.to_s.length >= 3 || description_matched.to_s.length >= 3

      # 配信開始時刻を調べる
      uri2 = URI.parse('https://www.googleapis.com/youtube/v3/videos')
      uri2.query = URI.encode_www_form(query2)
      req = Net::HTTP::Get.new(uri2.request_uri)
      res = http.request(req)
      begin
        body = JSON.parse(res.body).with_indifferent_access
        start_at = Time.parse(body[:items][0][:liveStreamingDetails][:actualStartTime])
      rescue StandardError => e
        raise
      end

      recent_streams = histories&.select do |m|
        # 直近で同じ人の配信を書き込んでいたら再度書かない
        m.text.include?("https://www.youtube.com/watch?v=#{stream[:id][:videoId]}") && m.timestamp + 6.hours > base_time
      end
      next unless recent_streams.empty?

      # 前回チェックから現在までに始まった配信でなければ無視する
      next unless (last_checked_time..base_time).cover?(start_at)

      # 簡易ブラックリスト
      next if channelTitle.include?('INNIN MAKERS')

      message = "#{channelTitle}さんの配信が始まりました
  配信名： #{title}
  URL: #{url}

※コメント等で過剰なコーチングをしないでください（配信主が求めた以上の情報を書き込まないでください）
ガイド禁止・ネタバレ禁止などの配信主のチャットルールを守り、視聴・コメントしてください
改善されない場合は、こちらの配信情報の通知を停止します
※参加型配信でない可能性があります。
  "
      ch.send_message(message)
    end
  rescue StandardError => e
    failed = true
    puts e.backtrace
    logger.fatal(e.backtrace)
  end

  unless failed
    # 最後に実行時間を記録して終了する
    db.execute('DELETE FROM last_twitch_crawler_times')
    insert_sql = 'INSERT INTO last_twitch_crawler_times VALUES(?)'
    db.execute(insert_sql, base_time.to_i)
  end
end

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
scope = 'https://www.googleapis.com/auth/calendar'
authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open('secret.json'),
  scope: scope
)

calendar_id_map = [
  {
    id: 'ls7g7e2bnqmfdq846r5f59mbjo@group.calendar.google.com',
    server_name: 'Sea of Thieves JPN',
    channel_name: 'イベント情報'
  },
  {
    id: '5spk3hufov8rcorh536do7dnr8@group.calendar.google.com',
    server_name: 'Skull and Bones Japan',
    channel_name: 'イベント情報'
  },
  {
    id: '3165c308f066046457982799753a6802ce52436733351bf01ea11549c798b471@group.calendar.google.com',
    server_name: '強制労働組合',
    channel_name: 'イベント情報'
  },
  {
    id: '5464be761e37d1aa835b43d4e3246e7cc0f1a5d7feab9fc90aa5e521a85c7a0b@group.calendar.google.com',
    server_name: '強制労働組合',
    channel_name: 'ユーザーイベント'
  }
]

# Google カレンダーをイベントに登録する
scheduler.cron '0 */2 * * *' do
  next unless COMMAND_PREFIX.include?('jack')

  authorizer.fetch_access_token!

  service = Google::Apis::CalendarV3::CalendarService.new
  service.authorization = authorizer

  base_time = DateTime.now

  calendar_id_map.each do |calendar|
    server_id, server = bot.servers.find { |_id, server| server.name == calendar[:server_name] }
    response = service.list_events(calendar[:id],
                                   max_results: 10,
                                   single_events: true,
                                   order_by: 'startTime',
                                   time_min: base_time.rfc3339)
    start_events = response.items
    start_events.each do |item|
      # イベント情報のみ登録する
      next if calendar[:channel_name] != 'イベント情報'
      # 開始済みのイベントはイベント登録できないのでしない
      next if item.start.date_time.to_time < Time.now

      begin
        insert_sql = 'INSERT INTO registered_events VALUES(?, ?)'
        sha256 = Digest::SHA256.new
        sha256.update(item.summary)
        sha256.update(item.start.date_time.to_time.iso8601)
        db.execute(insert_sql, sha256.hexdigest, item.summary)
        Discordrb::API::Server.create_scheduled_event(
          bot.token,
          server_id,
          nil, # channel_id (external のときは nil)
          { "location": 'ゲーム内' }, # metadata
          item.summary, # イベント名
          2, # privacy_level(2 => :guild_only)
          item.start.date_time.to_time.iso8601, # scheduled_start_time
          item.end.date_time.to_time.iso8601, # scheduled_end_time
          item.description ? Sanitize.clean(item.description&.gsub('<br>', "\n")) : '記載なし', # description
          3, # entity_type(1 => :stage, 2 => :voice, 3 => :external)
          1, # status(1 => :scheduled, 2 => :active, 3 => :completed, 4 => :canceled)
          nil # image
        )
      rescue StandardError => e
        next # 重複するイベントは登録しない
      end
    end
  end
end

# Discordのチャットに開始直前のイベント情報を流す
scheduler.cron '*/15 * * * *' do
  next unless COMMAND_PREFIX.include?('jack')

  authorizer.fetch_access_token!

  service = Google::Apis::CalendarV3::CalendarService.new
  service.authorization = authorizer

  base_time = Time.now
  calendar_id_map.each do |calendar|
    server_id, server = bot.servers.find { |_id, server| server.name == calendar[:server_name] }
    next if server.nil?
    next if server.text_channels.nil?

    ch = server.text_channels.find { |c| c.name.include?(calendar[:channel_name]) }
    response = service.list_events(calendar[:id],
                                   max_results: 10,
                                   single_events: true,
                                   order_by: 'startTime',
                                   time_min: base_time.rfc3339)

    now_starting_events = response.items.select do |item|
      ((base_time - 1.minutes)..(base_time + 1.minutes)).cover?(item.start.date_time.to_time)
    end

    now_starting_events.each do |item|
      next if item.nil?

      message = "◆◆◆イベント開始◆◆◆
  ■イベント名: #{item.summary}
  ■日時： <t:#{item.start.date_time.to_time.to_i}:F> - <t:#{item.end.date_time.to_time.to_i}:F> 開始: <t:#{item.start.date_time.to_time.to_i}:R> 終了: <t:#{item.end.date_time.to_time.to_i}:R>
  ■内容：
#{item.description ? Sanitize.clean(item.description&.gsub('<br>', "\n")) : '記載なし'}

  "
      m = ch.send_message(message)
    end
  end
end

# Discordのチャットにイベント情報を流す
scheduler.cron '0 18 * * *' do
  next unless COMMAND_PREFIX.include?('jack')

  authorizer.fetch_access_token!

  service = Google::Apis::CalendarV3::CalendarService.new
  service.authorization = authorizer

  base_time = DateTime.now
  calendar_id_map.each do |calendar|
    server_id, server = bot.servers.find { |_id, server| server.name == calendar[:server_name] }
    ch = server.text_channels.find { |c| c.name.include?(calendar[:channel_name]) }
    response = service.list_events(calendar[:id],
                                   max_results: 10,
                                   single_events: true,
                                   order_by: 'startTime',
                                   time_min: base_time.rfc3339)

    start_events = response.items.select do |item|
      # 本日開始のイベント
      (base_time.to_date..(base_time.to_date + 1.day)).cover?(item.start.date_time)
    end

    start_events.response.select do |item|
      ((base_time - 1.minutes)..(base_time + 1.minutes)).cover?(item.start.date_time)
    end

    if start_events.size > 0
      role = server.roles.find { |r| r.name == 'イベントハンター' }
      ch.send_message("<@&#{role.id}> のみんな！新しいイベント情報だ！") if role
      ch.send_message('---- 本日開始のイベント ----')
    end

    start_events.each do |item|
      next if item.nil?

      message = "■イベント名: #{item.summary}
  ■日時： <t:#{item.start.date_time.to_time.to_i}:F> - <t:#{item.end.date_time.to_time.to_i}:F> 開始: <t:#{item.start.date_time.to_time.to_i}:R> 終了: <t:#{item.end.date_time.to_time.to_i}:R>
  ■内容：
#{item.description ? Sanitize.clean(item.description&.gsub('<br>', "\n")) : '記載なし'}
  ----
  "
      m = ch.send_message(message)
    end

    end_events = response.items.select do |item|
      # 明日終了のイベント
      ((base_time.to_date + 1.day)..(base_time.to_date + 2.day)).cover?(item.end.date_time) && !(base_time.to_date..(base_time.to_date + 1.day)).cover?(item.start.date_time)
    end

    ch.send_message('---- 明日終了のイベント ----') if end_events.size > 0

    end_events.each do |item|
      message = "■イベント名: #{item.summary}
  ■日時： <t:#{item.start.date_time.to_time.to_i}:F> - <t:#{item.end.date_time.to_time.to_i}:F> 終了まで <t:#{item.end.date_time.to_time.to_i}:R>
  ■内容：
#{item.description ? Sanitize.clean(item.description&.gsub('<br>', "\n")) : '記載なし'}
  ----
  "
      m = ch.send_message(message)
    end
  end
end

scheduler.join
