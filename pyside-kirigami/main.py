import sys
import os
import gi
import threading
import platform
import signal

# Ensure GObject Introspection can find Pamac
gi.require_version('Pamac', '11')
from gi.repository import Pamac, GLib

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot, Signal, QTimer

class PamacBackend(QObject):
    search_results_ready = Signal(list)
    status_message = Signal(str)

    def __init__(self):
        super().__init__()
        
        # OS Detection
        self.is_arch = os.path.exists("/etc/arch-release")
        user_config_dir = os.path.expanduser("~/.config/pamac")
        self.user_db_path = os.path.expanduser("~/.local/share/pamac")
        os.makedirs(user_config_dir, exist_ok=True)
        
        if self.is_arch:
            self.conf_path = "/etc/pamac.conf" if os.path.exists("/etc/pamac.conf") else os.path.join(user_config_dir, "pamac.conf")
            # CRITICAL: libpamac needs PACMAN_CONF to find repos
            os.environ["PACMAN_CONF"] = "/etc/pacman.conf"
            print(f"Arch Linux: using {os.environ['PACMAN_CONF']}")
        else:
            self.conf_path = os.path.join(user_config_dir, "pamac.conf")
            user_pacman_conf = os.path.join(user_config_dir, "pacman.conf")
            os.makedirs(os.path.join(self.user_db_path, "sync"), exist_ok=True)
            os.environ["PACMAN_CONF"] = user_pacman_conf
            os.environ["PACMAN_DBPATH"] = self.user_db_path
            
            if not os.path.exists(user_pacman_conf):
                with open(user_pacman_conf, 'w') as f:
                    f.write(f"[options]\nDBPath = {self.user_db_path}\nSigLevel = Never\n\n"
                            "[core]\nServer = https://mirrors.kernel.org/archlinux/$repo/os/$arch\n"
                            "[extra]\nServer = https://mirrors.kernel.org/archlinux/$repo/os/$arch\n")

        if not os.path.exists(self.conf_path):
            with open(self.conf_path, 'w') as f:
                f.write("EnableAUR\n")

        os.environ["PAMAC_CONF"] = self.conf_path
        self._config = Pamac.Config(conf_path=self.conf_path)
        self._config.set_enable_aur(True)
        self._db = Pamac.Database(config=self._config)
        
        try:
            repos = list(self._db.get_repos_names())
            print(f"Recognized repos: {repos}")
        except Exception as e:
            print(f"Error listing repos: {e}")
        
        self._transaction = Pamac.Transaction(database=self._db)
        
        # Start background maintenance
        threading.Thread(target=self._bg_maintenance, daemon=True).start()

    def _bg_maintenance(self):
        sync_dir = os.path.join(self.user_db_path, "sync")
        if self.is_arch:
            aur_dest = "/var/lib/pacman/sync/packages-meta-ext-v1.json.gz"
            if not os.path.exists(aur_dest):
                sync_dir = os.path.expanduser("~/.local/share/pamac/sync")
                os.makedirs(sync_dir, exist_ok=True)
                self._download_aur_metadata(sync_dir)
        else:
            self._ensure_local_databases(self.user_db_path)
        
        GLib.idle_add(self._initial_refresh)

    def _download_aur_metadata(self, sync_dir):
        dest = os.path.join(sync_dir, "packages-meta-ext-v1.json.gz")
        if not os.path.exists(dest):
            self.status_message.emit("Downloading AUR metadata (12MB)...")
            self._download("https://aur.archlinux.org/packages-meta-ext-v1.json.gz", dest)
            self.status_message.emit("AUR metadata ready.")

    def _ensure_local_databases(self, db_path):
        sync_dir = os.path.join(db_path, "sync")
        arch = "x86_64"
        self.status_message.emit("Syncing databases...")
        for repo in ["core", "extra"]:
            url = f"https://mirrors.kernel.org/archlinux/{repo}/os/{arch}/{repo}.db"
            self._download(url, os.path.join(sync_dir, f"{repo}.db"))
        self._download_aur_metadata(sync_dir)
        self.status_message.emit("System ready.")

    def _download(self, url, dest):
        try:
            import urllib.request
            urllib.request.urlretrieve(url, dest)
        except Exception as e:
            print(f"Download failed: {e}")

    def _initial_refresh(self):
        self._transaction.check_dbs(None, lambda o, r: print("DB check done."))

    @Slot(str)
    def search_packages_async(self, query):
        threading.Thread(target=self._perform_search, args=(query,), daemon=True).start()

    def _perform_search(self, query):
        if not query or len(query) < 2:
            GLib.idle_add(self.search_results_ready.emit, [])
            return
        results = []
        try:
            # Search repos
            pkgs = self._db.search_pkgs(query)
            print(f"Search {query}: found {len(pkgs)} repo results")
            for pkg in pkgs:
                results.append({
                    "name": pkg.get_name(),
                    "version": pkg.get_version(),
                    "description": pkg.get_desc() or "",
                    "repository": pkg.get_repo() or "Repo"
                })
            # Search AUR
            aur_pkgs = self._db.search_aur_pkgs(query)
            print(f"Search {query}: found {len(aur_pkgs)} AUR results")
            for pkg in aur_pkgs:
                results.append({
                    "name": pkg.get_name(),
                    "version": pkg.get_version(),
                    "description": pkg.get_desc() or "",
                    "repository": "AUR"
                })
        except Exception as e:
            print(f"Search failed: {e}")
        GLib.idle_add(self.search_results_ready.emit, results)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = QGuiApplication(sys.argv)
    timer = QTimer()
    timer.start(500)
    timer.timeout.connect(lambda: None)
    engine = QQmlApplicationEngine()
    backend = PamacBackend()
    engine.rootContext().setContextProperty("pamacBackend", backend)
    engine.load(os.path.join(os.path.dirname(__file__), "Main.qml"))
    if not engine.rootObjects():
        sys.exit(-1)
    sys.exit(app.exec())
