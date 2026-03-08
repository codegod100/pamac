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
    search_started = Signal()
    status_message = Signal(str)

    def __init__(self):
        super().__init__()
        
        system_pacman_conf = "/etc/pacman.conf"
        user_config_dir = os.path.expanduser("~/.config/pamac")
        self.user_db_path = os.path.expanduser("~/.local/share/pamac")
        self.sync_dir = os.path.join(self.user_db_path, "sync")
        
        os.makedirs(user_config_dir, exist_ok=True)
        os.makedirs(self.sync_dir, exist_ok=True)
        
        # Setup environment
        os.environ["PACMAN_DBPATH"] = self.user_db_path
        os.environ["PACMAN_CONF"] = os.path.join(user_config_dir, "pacman.conf")
        self.conf_path = os.path.join(user_config_dir, "pamac.conf")
        os.environ["PAMAC_CONF"] = self.conf_path

        # Setup local pacman.conf if not on Arch
        if not os.path.exists(os.environ["PACMAN_CONF"]):
            with open(os.environ["PACMAN_CONF"], 'w') as f:
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
        # Symlink system DBs if possible
        system_sync = "/var/lib/pacman/sync"
        if os.path.exists(system_sync):
            for db in ["core.db", "extra.db"]:
                src = os.path.join(system_sync, db)
                dst = os.path.join(self.sync_dir, db)
                if os.path.exists(src) and not os.path.exists(dst):
                    try: os.symlink(src, dst)
                    except: pass

        # Ensure AUR metadata
        aur_dest = os.path.join(self.sync_dir, "packages-meta-ext-v1.json.gz")
        if not os.path.exists(aur_dest):
            self.status_message.emit("Downloading AUR metadata...")
            self._download("https://aur.archlinux.org/packages-meta-ext-v1.json.gz", aur_dest)
        
        self.status_message.emit("Ready")
        GLib.idle_add(self._initial_refresh)

    def _download(self, url, dest):
        try:
            import urllib.request
            urllib.request.urlretrieve(url, dest)
        except: pass

    def _initial_refresh(self):
        self._transaction.check_dbs(None, lambda o, r: None)

    @Slot(str, str, result="QVariantMap")
    def get_package_details(self, name, repo):
        try:
            pkg = None
            if repo == "AUR":
                pkg = self._db.get_aur_pkg(name)
            else:
                pkg = self._db.get_sync_pkg(name)
            
            if not pkg:
                return {}

            details = {
                "name": pkg.props.name,
                "version": pkg.props.version,
                "description": pkg.props.desc or "",
                "repository": repo,
                "url": pkg.props.url or "",
                "license": pkg.props.license or "",
                "maintainer": "",
            }

            if repo == "AUR":
                details["votes"] = str(pkg.props.numvotes)
                details["popularity"] = f"{pkg.props.popularity:.2f}"
                details["maintainer"] = pkg.props.maintainer or "None"
            else:
                details["maintainer"] = pkg.props.packager or ""
            
            # Final attempt at bulletproof dependency processing
            details["depends"] = []
            deps = pkg.props.depends
            if deps is not None:
                try:
                    # Try list-like or iterable
                    for d in deps:
                        details["depends"].append(str(d))
                except:
                    try:
                        # Try index-based access
                        length = 0
                        if hasattr(deps, "length"): length = deps.length
                        elif hasattr(deps, "len"): length = deps.len
                        else: length = len(deps)
                        
                        for i in range(length):
                            try:
                                d = deps.get(i) if hasattr(deps, "get") else deps[i]
                                if d: details["depends"].append(str(d))
                            except: break
                    except: pass
                
            return details
        except Exception as e:
            print(f"Failed to get details for {name}: {e}")
            return {}

    @Slot(str)
    def search_packages_async(self, query):
        self.search_started.emit()
        threading.Thread(target=self._perform_search, args=(query,), daemon=True).start()

    def _perform_search(self, query):
        if not query or len(query) < 2:
            GLib.idle_add(self.search_results_ready.emit, [])
            return
        results = []
        try:
            for pkg in self._db.search_pkgs(query):
                results.append({
                    "name": pkg.props.name,
                    "version": pkg.props.version,
                    "description": pkg.props.desc or "",
                    "repository": pkg.props.repo or "Repo"
                })
            for pkg in self._db.search_aur_pkgs(query):
                results.append({
                    "name": pkg.props.name,
                    "version": pkg.props.version,
                    "description": pkg.props.desc or "",
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
