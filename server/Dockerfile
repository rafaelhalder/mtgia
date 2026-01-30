FROM dart:stable

WORKDIR /app

# Dart Frog CLI (necessário para `dart_frog build`)
ENV PATH="$PATH:/root/.pub-cache/bin"
RUN dart pub global activate dart_frog_cli

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .

# Gera o servidor de produção (build/bin/server.dart)
RUN dart_frog build

ENV PORT=8080
EXPOSE 8080

# Easypanel costuma injetar PORT; fallback para 8080.
CMD ["/bin/sh", "-c", "dart build/bin/server.dart --hostname 0.0.0.0 --port ${PORT:-8080}"]
