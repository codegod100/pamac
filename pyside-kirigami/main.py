import sys
import os
import gi

# Ensure GObject Introspection can find Pamac
# In a real installation, these would be in standard paths
# For development, we rely on environment variables (GI_TYPELIB_PATH, LD_LIBRARY_PATH)

gi.require_version('Pamac', '11')
from gi.repository import Pamac, GLib

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QObject, Slot, Property, Signal

class PamacBackend(QObject):
    def __init__(self):
        super().__init__()
        
        # Setup user-local config and paths for Nix
        user_config_dir = os.path.expanduser("~/.config/pamac")
        user_config_path = os.path.join(user_config_dir, "pamac.conf")
        user_pacman_conf = os.path.join(user_config_dir, "pacman.conf")
        user_db_path = os.path.expanduser("~/.local/share/pamac")
        
        os.makedirs(user_config_dir, exist_ok=True)
        os.makedirs(os.path.join(user_db_path, "sync"), exist_ok=True)
        
        if not os.path.exists(user_pacman_conf):
            print(f"Creating user pacman.conf at {user_pacman_conf}")
            with open(user_pacman_conf, 'w') as f:
                f.write(f"[options]\nDBPath = {user_db_path}\n")
        
        # ALWAYS use our local pacman.conf for this prototype on Nix
        os.environ["PACMAN_CONF"] = user_pacman_conf
        os.environ["PACMAN_DBPATH"] = user_db_path
        
        if not os.path.exists(user_config_path):
            print(f"Creating user config at {user_config_path}")
            # Start with the system/store config as base
            base_conf = os.environ.get("PAMAC_CONF", "/etc/pamac.conf")
            content = ""
            if os.path.exists(base_conf):
                with open(base_conf, 'r') as f:
                    content = f.read()
            
            # Ensure DBPath is set to user-writable location
            import re
            if "DBPath" in content:
                content = re.sub(r"^#?DBPath\s*=.*$", f"DBPath = {user_db_path}", content, flags=re.MULTILINE)
            else:
                content += f"\nDBPath = {user_db_path}\n"
            
            # Ensure AUR is enabled
            content = content.replace("#EnableAUR", "EnableAUR")
            
            with open(user_config_path, 'w') as f:
                f.write(content)
        
        # ALWAYS use our local pamac.conf
        os.environ["PAMAC_CONF"] = user_config_path
        
        print(f"Using config: {user_config_path}")
        print(f"Using pacman config: {user_pacman_conf}")
        
        # Initializing Pamac objects
        self._config = Pamac.Config(conf_path=user_config_path)
        self._db = Pamac.Database(config=self._config)
        self._transaction = Pamac.Transaction(database=self._db)
        
        # Connect signals
        self._transaction.connect("emit-action", lambda obj, action: print(f"Action: {action}"))
        self._transaction.connect("emit-warning", lambda obj, msg: print(f"Warning: {msg}"))
        self._transaction.connect("emit-error", lambda obj, msg, details: print(f"Error: {msg} ({details})"))
        
        # Ensure AUR metadata exists
        self._ensure_aur_metadata(user_db_path)
        
        # Trigger an initial check for databases
        GLib.idle_add(self._initial_refresh)

    def _ensure_aur_metadata(self, db_path):
        aur_metadata_path = os.path.join(db_path, "sync", "packages-meta-ext-v1.json.gz")
        if not os.path.exists(aur_metadata_path):
            print("AUR metadata missing, downloading...")
            try:
                import urllib.request
                url = "https://aur.archlinux.org/packages-meta-ext-v1.json.gz"
                urllib.request.urlretrieve(url, aur_metadata_path)
                print("AUR metadata downloaded successfully.")
            except Exception as e:
                print(f"Failed to download AUR metadata: {e}")

    def _initial_refresh(self):
        print("Checking databases...")
        # Try a standard refresh via transaction (might fail without daemon but worth a try)
        self._transaction.check_dbs(None, self._on_check_dbs_done)

    def _on_check_dbs_done(self, obj, res):
        try:
            obj.check_dbs_finish(res)
            print("Database check complete.")
        except Exception as e:
            # Expected if daemon is missing
            pass
    
    @Slot(str, result="QVariantList")
    def search_packages(self, query):
        if not query or len(query) < 2:
            return []
        
        results = []
        
        # Repo packages
        try:
            pkgs = self._db.search_pkgs(query)
            for pkg in pkgs:
                results.append({
                    "name": pkg.get_name(),
                    "version": pkg.get_version(),
                    "description": pkg.get_desc() if pkg.get_desc() else "",
                    "repository": pkg.get_repo() if pkg.get_repo() else "Repo"
                })
        except Exception as e:
            print(f"Repo search failed: {e}")
            
        # AUR packages
        try:
            aur_pkgs = self._db.search_aur_pkgs(query)
            for pkg in aur_pkgs:
                results.append({
                    "name": pkg.get_name(),
                    "version": pkg.get_version(),
                    "description": pkg.get_desc() if pkg.get_desc() else "",
                    "repository": "AUR"
                })
        except Exception as e:
            print(f"AUR search failed: {e}")
            
        return results

if __name__ == "__main__":
    app = QGuiApplication(sys.argv)
    
    engine = QQmlApplicationEngine()
    backend = PamacBackend()
    engine.rootContext().setContextProperty("pamacBackend", backend)
    
    # Load Kirigami
    qml_file = os.path.join(os.path.dirname(__file__), "Main.qml")
    engine.load(qml_file)
    
    if not engine.rootObjects():
        sys.exit(-1)
    
    sys.exit(app.exec())
