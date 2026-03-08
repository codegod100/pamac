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
        
        # Setup environment variables before any GObject is created
        if self.is_arch:
            os.environ["PACMAN_CONF"] = "/etc/pacman.conf"
            os.environ["PAMAC_CONF"] = "/etc/pamac.conf" if os.path.exists("/etc/pamac.conf") else os.path.join(user_config_dir, "pamac.conf")
            os.environ["PACMAN_DBPATH"] = "/var/lib/pacman/"
        else:
            # Non-arch setup... (skipped for brevity but remains same logic)
            os.environ["PACMAN_CONF"] = os.path.join(user_config_dir, "pacman.conf")
            os.environ["PAMAC_CONF"] = os.path.join(user_config_dir, "pamac.conf")
            os.environ["PACMAN_DBPATH"] = self.user_db_path

        # Create objects
        self._config = Pamac.Config(conf_path=os.environ["PAMAC_CONF"])
        self._config.set_enable_aur(True)
        self._db = Pamac.Database(config=self._config)
        
        # VALIDATION: Check if we actually see the system repos
        repos = list(self._db.get_repos_names())
        print(f"DEBUG: PACMAN_CONF={os.environ.get('PACMAN_CONF')}")
        print(f"DEBUG: PACMAN_DBPATH={os.environ.get('PACMAN_DBPATH')}")
        print(f"DEBUG: Recognized repos: {repos}")
        
        if not repos:
            print("FATAL ERROR: No repositories detected! libpamac failed to load Arch databases.")
            print("Shutting down because I fucked it up.")
            sys.exit(1)
        
        self._transaction = Pamac.Transaction(database=self._db)
        threading.Thread(target=self._bg_maintenance, daemon=True).start()

    def _bg_maintenance(self):
        if not self.is_arch:
            self._ensure_local_databases(self.user_db_path)
        else:
            # Ensure AUR metadata
            sync_dir = os.path.expanduser("~/.local/share/pamac/sync")
            os.makedirs(sync_dir, exist_ok=True)
            self._download_aur_metadata(sync_dir)
        GLib.idle_add(self._initial_refresh)

    def _download_aur_metadata(self, sync_dir):
        dest = os.path.join(sync_dir, "packages-meta-ext-v1.json.gz")
        if not os.path.exists(dest):
            self.status_message.emit("Downloading AUR metadata...")
            try:
                import urllib.request
                urllib.request.urlretrieve("https://aur.archlinux.org/packages-meta-ext-v1.json.gz", dest)
            except Exception as e:
                print(f"AUR Download failed: {e}")

    def _initial_refresh(self):
        self._transaction.check_dbs(None, lambda o, r: None)

    @Slot(str)
    def search_packages_async(self, query):
        threading.Thread(target=self._perform_search, args=(query,), daemon=True).start()

    def _perform_search(self, query):
        if not query or len(query) < 2:
            GLib.idle_add(self.search_results_ready.emit, [])
            return
        results = []
        try:
            for pkg in self._db.search_pkgs(query):
                results.append({
                    "name": pkg.get_name(),
                    "version": pkg.get_version(),
                    "description": pkg.get_desc() or "",
                    "repository": pkg.get_repo() or "Repo"
                })
            for pkg in self._db.search_aur_pkgs(query):
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
