class Contourtty < Formula
  desc "Structure-aware ASCII terminal media renderer"
  homepage "https://github.com/gongahkia/strok"
  license "MIT"
  head "https://github.com/gongahkia/strok.git", branch: "main"

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build
  depends_on "ffmpeg"
  depends_on "zlib"

  def install
    system "cmake", "-S", ".", "-B", "build",
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_INSTALL_PREFIX=#{prefix}"
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    assert_match "contourtty", shell_output("#{bin}/contourtty --version")
  end
end
