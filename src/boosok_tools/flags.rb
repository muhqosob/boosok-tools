require 'sketchup'
require 'json'
require 'base64'
Sketchup.require 'boosok_tools/license'

module BoosokTools
  # Kill-switch fitur dari server: tool yang dimatikan sementara (mis. ditemukan bug) tidak bisa dibuka sampai
  # dihidupkan lagi lewat panel admin. Bisa untuk semua user atau hanya untuk key tertentu, dengan pesan bebas.
  # Daftar terakhir disimpan lokal, jadi tool yang dimatikan tetap mati walau SketchUp dibuka tanpa internet.
  module Flags
    PREF_SECT  = "BoosokTools"  unless defined?(PREF_SECT)
    PREF_FLAGS = "tool_flags"   unless defined?(PREF_FLAGS)
    INTERVAL   = 30 * 60        unless defined?(INTERVAL) # cek ulang tiap 30 menit selama SketchUp terbuka

    @flags = nil
    @fetching = false
    @timer = nil

    # {"tool_id" => "pesan"}; pesan boleh kosong
    def self.disabled
      @flags ||= load_cached
    end

    def self.disabled?(id)
      disabled.key?(id.to_s)
    end

    def self.message(id)
      disabled[id.to_s].to_s
    end

    def self.sanitize(raw)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(id, msg), h|
        h[id.to_s] = msg.to_s[0, 300] if id.to_s.match?(/\A[a-z0-9_]{1,40}\z/)
      end
    end

    # Disimpan sebagai base64 URL-safe: Sketchup.read_default meng-eval string, jadi JSON mentah bisa SyntaxError
    def self.load_cached
      raw = Sketchup.read_default(PREF_SECT, PREF_FLAGS, "").to_s
      raw.empty? ? {} : sanitize(JSON.parse(Base64.urlsafe_decode64(raw)))
    rescue StandardError, ScriptError
      {}
    end

    def self.save(flags)
      Sketchup.write_default(PREF_SECT, PREF_FLAGS, Base64.urlsafe_encode64(JSON.generate(flags), padding: false))
    rescue StandardError
      nil
    end

    # Ambil daftar terbaru dari server (async). Gagal / offline: daftar lama dipertahankan. Blok dipanggil dengan true
    # bila daftar berubah.
    def self.refresh(&callback)
      return unless License.online_configured? && !@fetching

      @fetching = true
      body = {}
      key = License.saved_mode == "online" ? License.saved_key : ""
      body[:key] = key unless key.empty?
      License.http_post("/flags", body) do |status, data|
        @fetching = false
        if status == 200 && data && data["ok"] && data["flags"].is_a?(Hash)
          fresh = sanitize(data["flags"])
          changed = fresh != disabled
          @flags = fresh
          save(fresh) if changed
          callback.call(changed) if callback
        end
      end
    rescue StandardError
      @fetching = false
    end

    # Cek saat startup, lalu berkala. Blok dipanggil bila daftar berubah.
    def self.start(&on_change)
      UI.stop_timer(@timer) if @timer
      UI.start_timer(6, false) { refresh(&on_change) }
      @timer = UI.start_timer(INTERVAL, true) { refresh(&on_change) }
    end
  end
end
