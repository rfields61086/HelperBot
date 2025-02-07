import xml.etree.ElementTree as ET

# Load XML
xml_file = "C:\\Users\\rfiel\\PycharmProjects\\Xml_Depends\\RedgateTestXML.xml"  # Replace with your XML file
tree = ET.parse(xml_file)
root = tree.getroot()

# Prepare Mermaid script
mermaid_script = ["graph TD;"]  # Start with Mermaid graph declaration

# Create a dictionary to store object names and their IDs
id_map = {}
object_counter = 0

# First pass: Assign unique IDs to each object
for obj in root.findall(".//Object"):
    obj_name = obj.find("Name").text if obj.find("Name") is not None else None
    if not obj_name:
        continue  # Skip objects with no name

    object_counter += 1
    obj_id = f"obj_{object_counter}"
    id_map[obj_name] = obj_id  # Store mapping of object name to ID

# Handle unresolved objects
unresolved_counter = 0
for obj in root.findall(".//Object/Uses/UnresolvedObject"):
    unresolved_name = obj.text
    if unresolved_name and unresolved_name not in id_map:
        unresolved_counter += 1
        unresolved_id = f"unresolved_{unresolved_counter}"
        id_map[unresolved_name] = unresolved_id
        mermaid_script.append(f"{unresolved_id}[\"{unresolved_name} (Unresolved)\"]")  # Add unresolved as a node

# Second pass: Process objects and add connections
for obj in root.findall(".//Object"):
    obj_name = obj.find("Name").text if obj.find("Name") is not None else None
    obj_id = id_map.get(obj_name, None)

    if not obj_name or not obj_id:
        continue  # Skip objects with no name or ID

    # Add the object as a node
    mermaid_script.append(f"{obj_id}[\"{obj_name}\"]")

    # Extract 'Uses' dependencies
    uses_elem = obj.find("Uses")
    if uses_elem is not None:
        for used in uses_elem.findall("Object"):
            if used.text in id_map:
                mermaid_script.append(f"{obj_id} --> {id_map[used.text]}")
        for unresolved in uses_elem.findall("UnresolvedObject"):
            if unresolved.text in id_map:
                mermaid_script.append(f"{obj_id} --> {id_map[unresolved.text]}")

    # Extract 'UsedBy' dependencies
    #used_by_elem = obj.find("UsedBy")
    #if used_by_elem is not None:
        #for user in used_by_elem.findall("Object"):
            #if user.text in id_map:
                #mermaid_script.append(f"{id_map[user.text]} --> {obj_id}")
        #for unresolved in used_by_elem.findall("UnresolvedObject"):
            #if unresolved.text in id_map:
                #mermaid_script.append(f"{id_map[unresolved.text]} --> {obj_id}")

# Combine the Mermaid script
mermaid_output = "\n".join(mermaid_script)

# Output the final Mermaid script
print(mermaid_output)
