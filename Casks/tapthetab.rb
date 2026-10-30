# Homebrew cask for TapTheTab, kept in this repository.
#   brew tap memoliertorerr/tapthetab https://github.com/memoliertorerr/tapthetab
#   brew install --cask tapthetab
# Bump with scripts/update-cask.sh after each release.
cask "tapthetab" do
  version "0.9.0"
  sha256 "4b107fe7fc1cfeee20bb4540f9ad5d2320818cf2a828048ff83d15f1204403b1"

  url "https://github.com/memoliertorerr/tapthetab/releases/download/v#{version}/TapTheTab-#{version}.dmg"
  name "TapTheTab"
  desc "Keyboard-first window switcher with type-to-search"
  homepage "https://github.com/memoliertorerr/tapthetab"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "TapTheTab.app"

  uninstall quit: "io.github.memoliertorerr.TapTheTab"

  zap trash: "~/Library/Application Support/TapTheTab"
end
