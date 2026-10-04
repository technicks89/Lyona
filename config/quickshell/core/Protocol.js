.pragma library

// The one rule for a helper protocol's header line, "NAME<TAB>MAJOR[<TAB>MINOR]"
// (Sync Sprint 16 R16-53). The models parsed it three ways: exactly three
// fields with minor 0, three or more, or the major alone. The protocols are
// append-only, so a reader takes any minor of the major it knows, and ignores
// records it does not.

// FIELDS (a line split on tabs) is the header of protocol NAME, version MAJOR.
function isHeader(fields, name, major) {
    return fields.length > 0 && fields[0] === name && validHeader(fields, major);
}

// FIELDS, already known to be some protocol's header, is version MAJOR: the
// major matches, and the minor, when there is one, is a number. Nothing follows.
function validHeader(fields, major) {
    if (fields.length < 2 || fields.length > 3 || fields[1] !== String(major))
        return false;
    return fields.length === 2 || /^[0-9]+$/.test(fields[2]);
}
