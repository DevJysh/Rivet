# Maintainer: DevJysh
#
# Builds Rivet from its git repository, with the Goose compiler built from
# source at the release tag below (Goose is not in the Arch repositories).
# Untested here: check it with `makepkg -si` before relying on it.
#
# Point the Rivet source at the branch or tag you want, for example
#   git+https://github.com/DevJysh/Rivet.git#branch=main

pkgname=rivet
pkgver=0.1.0
pkgrel=1
pkgdesc='A minimal AppImage installer written in Goose'
arch=('x86_64')
url='https://github.com/DevJysh/Rivet'
license=('MIT')
depends=('glibc')
makedepends=('git' 'cmake' 'gcc' 'python')
optdepends=(
  'fuse2: needed to run AppImages normally (Rivet itself does not need it)'
  'desktop-file-utils: refreshes the desktop database after install'
  'tk: needed by rivet-gui'
  'xdg-utils: needed by rivet register'
)
source=(
  "$pkgname::git+https://github.com/DevJysh/Rivet.git"
  "goose::git+https://github.com/aardappel/goose.git#tag=v2026.4"
)
sha256sums=('SKIP' 'SKIP')

build() {
  cmake -S goose -B goose-build -DCMAKE_BUILD_TYPE=Release
  cmake --build goose-build --config Release
  make -C "$pkgname" GOOSE="$srcdir/goose-build/goose"
}

check() {
  make -C "$pkgname" GOOSE="$srcdir/goose-build/goose" test
}

package() {
  make -C "$pkgname" GOOSE="$srcdir/goose-build/goose" DESTDIR="$pkgdir" PREFIX=/usr install
  install -Dm644 "$pkgname/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 "$pkgname/README.md" "$pkgdir/usr/share/doc/$pkgname/README.md"
}
