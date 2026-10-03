module BoosokTools::SelectTool
  # Dialog UI HTML sudah ditiadakan sesuai permintaan user,
  # Tampilan digantikan sepenuhnya oleh in-viewport native overlay pada DrawHandler.
  class UiInfoHandler
    def initialize(tool); end
    def show; end
    def close; end
    def update_position(x, y); end
    def update_content; end
  end
end
