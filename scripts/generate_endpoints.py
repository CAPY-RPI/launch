import os
import sys
import yaml
import re
from dotenv import load_dotenv

load_dotenv()


def get_domain():
    domain_name = os.environ.get("DOMAIN_NAME")
    if not domain_name:
        if len(sys.argv) > 1:
            domain_name = sys.argv[1]
        else:
            print(
                "Error: DOMAIN_NAME environment variable not set and not provided as argument."
            )
            sys.exit(1)
    return domain_name.strip()


def find_docker_compose_files(root_dir):
    compose_files = []
    for root, dirs, files in os.walk(root_dir):
        if "docker-compose.yml" in files:
            compose_files.append(os.path.join(root, "docker-compose.yml"))
    return compose_files


def parse_compose_file(file_path, domain_name):
    endpoints = []
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return []

    if not data or "services" not in data:
        return []

    for service_name, service_config in data["services"].items():
        if not service_config:
            continue

        labels = service_config.get("labels", [])
        if not labels:
            continue

        label_dict = {}
        if isinstance(labels, list):
            for label in labels:
                if "=" in label:
                    key, value = label.split("=", 1)
                    label_dict[key.strip()] = value.strip()
        elif isinstance(labels, dict):
            label_dict = {str(k).strip(): str(v).strip() for k, v in labels.items()}

        if str(label_dict.get("traefik.enable")).lower() == "true":
            # Extract port
            port = "80"  # Default
            for key, value in label_dict.items():
                if key.endswith(".loadbalancer.server.port"):
                    port = value
                    break

            # Extract custom gatus path
            gatus_path = label_dict.get("gatus.path", "").strip()
            if not gatus_path.startswith("/") and gatus_path:
                gatus_path = "/" + gatus_path

            # Extract container name (fallback to service name)
            container_name = service_config.get("container_name", service_name).strip()

            # Find Host rules
            for key, value in label_dict.items():
                if key.startswith("traefik.http.routers.") and key.endswith(".rule"):
                    match = re.search(r"Host\(`([^`]+)`\)", value)
                    if match:
                        full_host = match.group(1)
                        final_host = full_host.replace(
                            "${DOMAIN_NAME}", domain_name
                        ).strip()

                        display_name = label_dict.get(
                            "homepage.name", service_name.capitalize()
                        ).strip()
                        original_group = label_dict.get(
                            "homepage.group", "Services"
                        ).strip()

                        endpoints.append(
                            {
                                "display_name": display_name,
                                "public_host": final_host,
                                "container_name": container_name,
                                "port": port,
                                "path": gatus_path,
                                "original_group": original_group,
                            }
                        )
                        # Multi-router services (like shlink) might have multiple rules.
                        # We want to capture all unique public hosts.

    return endpoints


def generate_gatus_config(domain_name, endpoints):
    print(f"Generating Gatus config for domain: {domain_name}")
    output_lines = []

    # Header
    output_lines.append("# Gatus Configuration - Generated")
    output_lines.append("storage:")
    output_lines.append("  type: sqlite")
    output_lines.append("  path: /data/data.db")
    output_lines.append("")

    output_lines.append("ui:")
    output_lines.append('  title: "Service Status"')
    output_lines.append('  header: "Uptime Monitor"')
    output_lines.append("")

    output_lines.append("endpoints:")

    # Always include internal health check
    output_lines.append("  - name: gatus-internal")
    output_lines.append('    group: "Core Infrastructure"')
    output_lines.append('    url: "http://localhost:8080/health"')
    output_lines.append("    interval: 1m")
    output_lines.append("    conditions:")
    output_lines.append('      - "[STATUS] == 200"')
    output_lines.append("")

    # Sort endpoints by display_name for consistent output
    endpoints.sort(key=lambda x: x["display_name"])

    # 1. External (Public) Group
    seen_urls = set()
    for endpoint in endpoints:
        url = f"https://{endpoint['public_host']}{endpoint['path']}"
        if url in seen_urls:
            continue
        seen_urls.add(url)

        # To satisfy Gatus uniqueness (Name + Group must be unique)
        name = f"{endpoint['display_name']} ({endpoint['public_host']})"

        output_lines.append(f'  - name: "{name}"')
        output_lines.append('    group: "Public"')
        output_lines.append(f'    url: "{url}"')
        output_lines.append("    interval: 1m")
        output_lines.append("    conditions:")
        output_lines.append('      - "[STATUS] == 200"')
        output_lines.append("")

    # 2. Internal (Cluster) Group
    # Deduplicate by container_name + port + path
    seen_internal = set()
    for endpoint in endpoints:
        ident = f"{endpoint['container_name']}:{endpoint['port']}{endpoint['path']}"
        if ident in seen_internal:
            continue
        seen_internal.add(ident)

        url = (
            f"http://{endpoint['container_name']}:{endpoint['port']}{endpoint['path']}"
        )
        name = f"{endpoint['display_name']} ({endpoint['container_name']})"

        output_lines.append(f'  - name: "{name}"')
        output_lines.append('    group: "Internal"')
        output_lines.append(f'    url: "{url}"')
        output_lines.append("    interval: 1m")
        output_lines.append("    conditions:")
        output_lines.append('      - "[STATUS] == 200"')
        output_lines.append("")

    # Go up one level from scripts/ to get to repo root
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_path = os.path.join(repo_root, "docker/system/gatus/config/config.yaml")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(output_lines))
    print(f"Successfully generated {output_path}")


def main():
    domain_name = get_domain()
    # Go up one level from scripts/ to get to repo root
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    print(f"Scanning for docker-compose.yml files in {root_dir}...")
    compose_files = find_docker_compose_files(root_dir)

    all_endpoints = []
    for cf in compose_files:
        endpoints = parse_compose_file(cf, domain_name)
        all_endpoints.extend(endpoints)

    print(f"Found {len(all_endpoints)} services with Traefik enabled.")
    generate_gatus_config(domain_name, all_endpoints)


if __name__ == "__main__":
    main()
