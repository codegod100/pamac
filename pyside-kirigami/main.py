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
        
        system_pacman_conf = "/etc/pacman.conf"
        system_db_path = "/var/lib/pacman/"
        
        user_config_dir = os.path.expanduser("~/.config/pamac")
        self.user_db_path = os.path.expanduser("~/.local/share/pamac")
        self.sync_dir = os.path.join(self.user_db_path, "sync")
        
        os.makedirs(user_config_dir, exist_ok=True)
        os.makedirs(self.sync_dir, exist_ok=True)
        
        # Setup environment variables for libpamac
        if os.path.exists(system_pacman_conf) and os.path.exists(system_db_path):
            os.environ["PACMAN_CONF"] = system_pacman_conf
            os.environ["PACMAN_DBPATH"] = system_db_path
            self.is_arch = True
        else:
            os.environ["PACMAN_CONF"] = os.path.join(user_config_dir, "pacman.conf")
            os.environ["PACMAN_DBPATH"] = self.user_db_path
            self.is_arch = False

        self.conf_path = os.path.join(user_config_dir, "pamac.conf")
        os.environ["PAMAC_CONF"] = self.conf_path

        # Setup local pacman.conf if not on Arch
        if not self.is_arch:
            user_pacman_conf = os.environ["PACMAN_CONF"]
            if not os.path.exists(user_pacman_conf):
                with open(user_pacman_conf, 'w') as f:
                    f.write(f"[options]\nDBPath = {self.user_db_path}\nSigLevel = Never\n\n"
                            "[core]\nServer = https://mirrors.kernel.org/archlinux/$repo/os/$arch\n"
                            "[extra]\nServer = https://mirrors.kernel.org/archlinux/$repo/os/$arch\n")

        if not os.path.exists(self.conf_path):
            with open(self.conf_path, 'w') as f:
                f.write("EnableAUR\n")

        # Initializing Pamac objects
        self._config = Pamac.Config(conf_path=self.conf_path)
        self._config.set_enable_aur(True)
        self._db = Pamac.Database(config=self._config)
        self._transaction = Pamac.Transaction(database=self._db)
        
        threading.Thread(target=self._bg_maintenance, daemon=True).start()

    def _bg_maintenance(self):
        if not self.is_arch:
            self._ensure_local_databases(self.user_db_path)
        else:
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

    def _ensure_local_databases(self, db_path):
        sync_dir = os.path.join(db_path, "sync")
        arch = "x86_64"
        self.status_message.emit("Syncing databases...")
        for repo in ["core", "extra"]:
            url = f"https://mirrors.kernel.org/archlinux/{repo}/os/{arch}/{repo}.db"
            dest = os.path.join(sync_dir, f"{repo}.db")
            if not os.path.exists(dest):
                try:
                    import urllib.request
                    urllib.request.urlretrieve(url, dest)
                except: pass
        self._download_aur_metadata(sync_dir)
        self.status_message.emit("Ready")

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
