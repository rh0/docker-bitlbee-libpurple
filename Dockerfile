ARG ALPINE_VERSION=3.12

FROM alpine:${ALPINE_VERSION} as bitlbee-build

ARG BITLBEE_VERSION=3.6

RUN apk add --no-cache --update \
    bash shadow build-base git python2 autoconf automake libtool mercurial intltool flex \
    glib-dev openssl-dev pidgin-dev json-glib-dev libgcrypt-dev zlib-dev libwebp-dev \
    libpng-dev protobuf-c-dev libxml2-dev discount-dev sqlite-dev http-parser-dev libotr-dev \
 && cd /tmp \
 && git clone -n https://github.com/bitlbee/bitlbee.git \
 && cd bitlbee \
 && git checkout ${BITLBEE_VERSION} \
 && ./configure --purple=1 --otr=plugin --ssl=openssl --prefix=/usr --etcdir=/etc/bitlbee \
 && make \
 && make install-bin \
 && make install-doc \
 && make install-dev \
 && make install-etc \
 && strip /usr/sbin/bitlbee \
 && touch /nowhere

# ---

FROM bitlbee-build as otr-install

ARG OTR=1

RUN echo OTR=${OTR} > /tmp/status \
 && if [ ${OTR} -eq 1 ]; \
     then cd /tmp/bitlbee \
       && make install-plugin-otr; \
     else mkdir -p /usr/lib/bitlbee \
       && ln -sf /nowhere /usr/lib/bitlbee/otr.so; \
    fi

# ---

FROM bitlbee-build as hangouts-build

ARG HANGOUTS=1
ARG HANGOUTS_VERSION=efa7a53

RUN echo HANGOUTS=${HANGOUTS} > /tmp/status \
 && if [ ${HANGOUTS} -eq 1 ]; \
     then cd /tmp \
       && git clone -n https://github.com/EionRobb/purple-hangouts.git \
       && cd purple-hangouts \
       && git checkout ${HANGOUTS_VERSION} \
       && make \
       && make install \
       && strip /usr/lib/purple-2/libhangouts.so; \
     else mkdir -p /usr/lib/purple-2 \
       && ln -sf /nowhere /usr/lib/purple-2/libhangouts.so; \
    fi

# ---

FROM bitlbee-build as discord-build

ARG DISCORD=1
ARG DISCORD_VERSION=0.4.3

RUN echo DISCORD=${DISCORD} > /tmp/status \
 && if [ ${DISCORD} -eq 1 ]; \
     then cd /tmp \
       && git clone -n https://github.com/sm00th/bitlbee-discord.git \
       && cd bitlbee-discord \
       && git checkout ${DISCORD_VERSION} \
       && ./autogen.sh \
       && ./configure --prefix=/usr \
       && make \
       && make install \
       && strip /usr/lib/bitlbee/discord.so; \
     else mkdir -p /usr/lib/bitlbee \
       && ln -sf /nowhere /usr/lib/bitlbee/discord.so \
       && ln -sf /nowhere /usr/lib/bitlbee/discord.la \
       && ln -sf /nowhere /usr/share/bitlbee/discord-help.txt; \
    fi

# ---

FROM alpine:${ALPINE_VERSION} as bitlbee-plugins

COPY --from=bitlbee-build /usr/sbin/bitlbee /tmp/usr/sbin/bitlbee
COPY --from=bitlbee-build /usr/share/man/man8/bitlbee.8 /tmp/usr/share/man/man8/bitlbee.8
COPY --from=bitlbee-build /usr/share/man/man5/bitlbee.conf.5 /tmp/usr/share/man/man5/bitlbee.conf.5
COPY --from=bitlbee-build /usr/share/bitlbee /tmp/usr/share/bitlbee
COPY --from=bitlbee-build /usr/lib/pkgconfig/bitlbee.pc /tmp/usr/lib/pkgconfig/bitlbee.pc
COPY --from=bitlbee-build /etc/bitlbee /tmp/etc/bitlbee

COPY --from=otr-install /usr/lib/bitlbee/otr.so /tmp/usr/lib/bitlbee/otr.so
COPY --from=otr-install /tmp/status /tmp/plugin/otr

COPY --from=hangouts-build /usr/lib/purple-2/libhangouts.so /tmp/usr/lib/purple-2/libhangouts.so
COPY --from=hangouts-build /tmp/status /tmp/plugin/hangouts

COPY --from=discord-build /usr/lib/bitlbee/discord.so /tmp/usr/lib/bitlbee/discord.so
COPY --from=discord-build /usr/lib/bitlbee/discord.la /tmp/usr/lib/bitlbee/discord.la
COPY --from=discord-build /usr/share/bitlbee/discord-help.txt /tmp/usr/share/bitlbee/discord-help.txt
COPY --from=discord-build /tmp/status /tmp/plugin/discord

RUN apk add --update --no-cache findutils \
 && find /tmp/ -type f -empty -delete \
 && find /tmp/ -type d -empty -delete \
 && cat /tmp/plugin/* > /tmp/plugins \
 && rm -rf /tmp/plugin

# ---

FROM alpine:${ALPINE_VERSION} as bitlbee-libpurple

COPY --from=bitlbee-plugins /tmp/ /

ARG PKGS="tzdata bash glib libssl1.1 libpurple libpurple-xmpp \
      libpurple-oscar libpurple-bonjour"

RUN addgroup -g 101 -S bitlbee \
 && adduser -u 101 -D -S -G bitlbee bitlbee \
 && install -d -m 750 -o bitlbee -g bitlbee /var/lib/bitlbee \
 && source /plugins \
 && if [ ${OTR} -eq 1 ]; then PKGS="${PKGS} libotr"; fi \
 && if [ ${FACEBOOK} -eq 1 ] || [ ${SKYPEWEB} -eq 1 ] || [ ${HANGOUTS} -eq 1 ] \
 || [ ${ROCKETCHAT} -eq 1 ] || [ ${MATRIX} -eq 1 ] || [ ${SIGNAL} -eq 1 ] \
 || [ ${ICYQUE} -eq 1 ]; then PKGS="${PKGS} json-glib"; fi \
 && if [ ${STEAM} -eq 1 ] || [ ${TELEGRAM} -eq 1 ] || [ ${MATRIX} -eq 1 ]; then PKGS="${PKGS} libgcrypt"; fi \
 && if [ ${TELEGRAM} -eq 1 ]; then PKGS="${PKGS} zlib libwebp libpng"; fi \
 && if [ ${HANGOUTS} -eq 1 ] || [ ${SIGNAL} -eq 1 ]; then PKGS="${PKGS} protobuf-c"; fi \
 && if [ ${SIPE} -eq 1 ]; then PKGS="${PKGS} libxml2"; fi \
 && if [ ${ROCKETCHAT} -eq 1 ]; then PKGS="${PKGS} discount"; fi \
 && if [ ${MATRIX} -eq 1 ]; then PKGS="${PKGS} sqlite http-parser"; fi \
 && apk add --no-cache --update ${PKGS} \
 && rm /plugins

EXPOSE 6667

CMD [ "/usr/sbin/bitlbee", "-F", "-n", "-u", "bitlbee" ]
