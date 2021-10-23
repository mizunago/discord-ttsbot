# Setup
## Configure docker-compose.yml
* AWS で Polly のフルアクセス権限がある IAM ユーザを作成、AccessKey/Secret を発行
* [Discord の開発者ポータル](https://discord.com/developers/applications) から Bot 用のトークンを発行、Bot を利用したいチャンネルに参加させる
  * Privileged Gateway Intents の Presence Intent, Server Members Intent が必要っぽい？
  * OAuth2 ページで必要な権限の URL を作成して、BOT を参加させる(以下はたぶん必須)
    * Scopes: bot
    * Bot Permissions
       * Text Permissions: Send Messages, Send TTS Messages
       * Voice Permissions: Connect, Speak
* 上記情報を元に, `docker-compose.yml` を修正する
  * 対象チャンネルは `- TTS_CHANNELS=#channel1,#channel2,#channel3` のように記述
* デフォルトでは VOICEVOX を使いますが、VOICEVOX と通信できなかった場合は AWS Polly を使います
  * VOICEVOX は CPU, メモリリソースを結構食うので使わない場合は docker-compose.yml から設定を削除してください
  * オンオフ設定はないので、通信を試すのでちょっとタイムアウトまでに時間がかかるかも

## Run container
```
docker-build .
docker-compose up -d
```

# Command
以下コマンドをdiscordのテキストチャットで実行できます
* `!connect`
    * 現在接続しているボイスチャンネルに読み上げBOTを接続します
* `!destroy`
    * 現在接続しているボイスチャンネルから読み上げBOTを切断します
* `!chname [呼ばれたい名前]`
    * 読み上げる際に、 `XXXXさんの発言` という説明が入ります。その際の `XXXX` を変更できます
