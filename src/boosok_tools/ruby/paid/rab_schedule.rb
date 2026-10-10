# Time schedule / kurva S dari hasil RAB. Murni hitungan (dipakai Excel dan PDF).
#   Tiap pekerjaan punya bobot (jumlah / total sebelum PPN), minggu mulai, dan durasi (minggu). Bobot dibagi rata ke minggu-minggu
#   durasinya; jumlah per minggu lalu dikumulatifkan jadi kurva S. Mulai & durasi awal disebar otomatis (berjenjang) dan bisa
#   diubah user di Excel; kurva S di Excel dihitung ulang oleh rumus.
module BoosokTools::RabSchedule
  DEFAULT_WEEKS = 12 unless defined?(DEFAULT_WEEKS)
  MIN_WEEKS = 2 unless defined?(MIN_WEEKS)
  MAX_WEEKS = 104 unless defined?(MAX_WEEKS)

  def self.weeks(value)
    n = Integer(value, exception: false) || DEFAULT_WEEKS
    n.clamp(MIN_WEEKS, MAX_WEEKS)
  end

  # Mulai & durasi awal untuk n pekerjaan: berjenjang dari minggu 1 sampai pekerjaan terakhir selesai di minggu terakhir.
  # Return [[mulai, durasi], ...]
  def self.defaults(count, weeks)
    return [] if count <= 0
    return [[1, weeks]] if count == 1

    dur = [[(weeks * 0.35).ceil, 2].max, weeks].min
    last_start = weeks - dur + 1
    Array.new(count) { |i| [1 + ((last_start - 1) * i / (count - 1.0)).round, dur] }
  end

  # report['rows'] -> { weeks:, items: [{ row:, start:, dur:, bobot:, weekly: [...] }], weekly: [...], cumulative: [...] }
  def self.compute(report, weeks)
    weeks = self.weeks(weeks)
    rows = report['rows']
    total = rows.sum { |r| r['jumlah'].to_f }
    plan = defaults(rows.size, weeks)
    items = rows.each_with_index.map do |row, i|
      start, dur = plan[i]
      bobot = total.positive? ? row['jumlah'].to_f / total : 0.0
      weekly = (1..weeks).map { |w| w >= start && w <= start + dur - 1 ? bobot / dur : 0.0 }
      { row: row, start: start, dur: dur, bobot: bobot, weekly: weekly }
    end
    weekly = (0...weeks).map { |w| items.sum { |it| it[:weekly][w] } }
    run = 0.0
    cumulative = weekly.map { |v| run += v }
    { weeks: weeks, items: items, weekly: weekly, cumulative: cumulative }
  end
end

file_loaded(__FILE__)
