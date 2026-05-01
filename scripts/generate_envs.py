import json
import os
import sys


def main():
    try:
        # Load the Terraform JSON output
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        print("Error: Input is not valid JSON.", file=sys.stderr)
        sys.exit(1)

    # Resolve the environment_files object
    env_files = data.get("environment_files", {}).get("value", {})
    if not env_files:
        print(
            "Skipping: No environment_files mapping found in Terraform output.",
            file=sys.stderr,
        )
        return

    for file_path, variables in env_files.items():
        # Ensure parent directory exists
        parent_dir = os.path.dirname(file_path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)

        # Build the .env file content
        content = []
        for key, value in sorted(variables.items()):
            content.append(f"{key}={value}")

        # Write the file
        try:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write("\n".join(content) + "\n")
            print(f"Generated: {file_path}")
        except IOError as e:
            print(f"Error: Failed to write to {file_path}: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
