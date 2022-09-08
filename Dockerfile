FROM ruby:2.7.5
RUN apt-get update && apt-get install -y \
    locales \
    locales-all \
    libopus-dev \
    ffmpeg \
    libopus0 \
    libsodium-dev \
    software-properties-common \
    imagemagick
RUN apt-get update && apt-get install -y tesseract-ocr libtesseract-dev tesseract-ocr-jpn  tesseract-ocr-script-jpan \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile /app/
ENV LANG ja_JP.UTF-8
RUN bundle install
COPY discord_voicebot.rb /app/
COPY voicevox.rb /app/
COPY deepl_trans.rb /app/
COPY secret.json /app/
COPY twitch_secret.yml /app/
COPY youtube_secret.yml /app/
COPY twitter_secret.yml /app/
CMD ["bundle", "exec", "ruby", "discord_voicebot.rb"]