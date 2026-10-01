import Foundation

nonisolated enum LanguageRegistry {

    static let plainText = Language(id: "plain", name: "Plain Text", extensions: ["txt", "text", "log"], scanner: .plain)

    static let markdown = Language(id: "markdown", name: "Markdown", extensions: ["md", "markdown", "mdown", "mkd", "mdx"], scanner: .markdown)

    static let csv = Language(id: "csv", name: "CSV", extensions: ["csv"], scanner: .plain)
    static let tsv = Language(id: "tsv", name: "Tab-Separated Values", extensions: ["tsv", "tab"], scanner: .plain)

    // MARK: Shared rule sets

    private static let cStrings: [StringRule] = [
        StringRule(open: "\"", close: "\""),
        StringRule(open: "'", close: "'", maxLength: 12),
    ]
    private static let cComments = [BlockCommentRule(start: "/*", end: "*/")]
    private static let cLiterals: Set<String> = ["true", "false", "null", "NULL", "nullptr", "nil"]

    // MARK: Languages

    static let swift = Language(
        id: "swift", name: "Swift", extensions: ["swift"],
        keywords: ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw", "switch", "where", "while", "Any", "as", "await", "async", "is", "self", "Self", "super", "throws", "try", "some", "any", "actor", "nonisolated", "isolated", "consuming", "borrowing", "macro", "package", "override", "final", "lazy", "weak", "unowned", "mutating", "nonmutating", "convenience", "required", "indirect", "dynamic", "optional", "infix", "prefix", "postfix", "willSet", "didSet", "get", "set", "each", "sending"],
        types: ["Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float", "Bool", "String", "Character", "Array", "Dictionary", "Set", "Optional", "Result", "Void", "Never", "Error", "Substring", "Range", "ClosedRange", "URL", "Data", "Date", "UUID"],
        literals: ["true", "false", "nil"],
        lineComments: ["//"],
        blockComments: [BlockCommentRule(start: "/*", end: "*/", nested: true)],
        strings: [
            StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true),
            StringRule(open: "#\"", close: "\"#", escape: false),
            StringRule(open: "\"", close: "\""),
        ],
        preprocessorPrefixes: ["#if", "#else", "#elseif", "#endif", "#available", "#unavailable", "#warning", "#error", "#selector", "#keyPath", "#file", "#line", "#function", "#Preview", "#expect", "#require"],
        annotationPrefixes: ["@"],
        uppercaseIdentifiersAreTypes: true
    )

    static let objectiveC = Language(
        id: "objc", name: "Objective-C", extensions: ["m", "mm", "h"],
        keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "@interface", "@implementation", "@end", "@property", "@synthesize", "@dynamic", "@protocol", "@class", "@selector", "@try", "@catch", "@finally", "@throw", "@synchronized", "@autoreleasepool", "@import", "@optional", "@required", "@public", "@private", "@protected", "self", "super", "in", "out", "inout", "instancetype", "id", "strong", "weak", "copy", "assign", "nonatomic", "atomic", "readonly", "readwrite", "nullable", "nonnull", "__block", "__weak", "__strong", "typeof", "BOOL", "YES", "NO"],
        types: ["NSString", "NSArray", "NSDictionary", "NSNumber", "NSObject", "NSInteger", "NSUInteger", "CGFloat", "NSError", "NSData", "NSDate", "NSURL", "NSSet", "NSMutableArray", "NSMutableDictionary", "NSMutableString"],
        literals: ["YES", "NO", "nil", "NULL", "true", "false"],
        lineComments: ["//"], blockComments: cComments,
        strings: [StringRule(open: "\"", close: "\"", prefixes: ["@"]), StringRule(open: "'", close: "'", maxLength: 8)],
        identifierChars: "@",
        preprocessorPrefixes: ["#"],
        uppercaseIdentifiersAreTypes: true
    )

    static let c = Language(
        id: "c", name: "C", extensions: ["c"],
        keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Bool", "_Complex", "_Atomic", "_Static_assert", "_Thread_local", "_Alignas", "_Alignof", "_Generic", "_Noreturn"],
        types: ["size_t", "ssize_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "uintptr_t", "intptr_t", "FILE", "bool", "wchar_t", "ptrdiff_t"],
        literals: cLiterals,
        lineComments: ["//"], blockComments: cComments, strings: cStrings,
        preprocessorPrefixes: ["#"]
    )

    static let cpp = Language(
        id: "cpp", name: "C++", extensions: ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "c++", "h++", "ipp", "tpp"],
        keywords: c.keywords.union(["alignas", "alignof", "and", "and_eq", "asm", "bitand", "bitor", "bool", "catch", "char16_t", "char32_t", "char8_t", "class", "compl", "concept", "consteval", "constexpr", "constinit", "const_cast", "co_await", "co_return", "co_yield", "decltype", "delete", "dynamic_cast", "explicit", "export", "false", "friend", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected", "public", "reinterpret_cast", "requires", "static_assert", "static_cast", "template", "this", "thread_local", "throw", "true", "try", "typeid", "typename", "using", "virtual", "wchar_t", "xor", "xor_eq", "override", "final"]),
        types: c.types.union(["string", "vector", "map", "unordered_map", "set", "unordered_set", "pair", "tuple", "shared_ptr", "unique_ptr", "weak_ptr", "optional", "variant", "array", "deque", "list", "queue", "stack", "string_view", "span", "function", "istream", "ostream", "iostream"]),
        literals: cLiterals,
        lineComments: ["//"], blockComments: cComments,
        strings: [StringRule(open: "R\"(", close: ")\"", escape: false, multiline: true)] + cStrings,
        preprocessorPrefixes: ["#"]
    )

    static let csharp = Language(
        id: "csharp", name: "C#", extensions: ["cs", "csx"],
        keywords: ["abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char", "checked", "class", "const", "continue", "decimal", "default", "delegate", "do", "double", "else", "enum", "event", "explicit", "extern", "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in", "int", "interface", "internal", "is", "lock", "long", "namespace", "new", "object", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sbyte", "sealed", "short", "sizeof", "stackalloc", "static", "string", "struct", "switch", "this", "throw", "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using", "virtual", "void", "volatile", "while", "add", "alias", "ascending", "async", "await", "by", "descending", "dynamic", "equals", "from", "get", "global", "group", "init", "into", "join", "let", "managed", "nameof", "nint", "notnull", "nuint", "on", "orderby", "partial", "record", "remove", "required", "scoped", "select", "set", "unmanaged", "value", "var", "when", "where", "with", "yield", "file", "and", "or", "not"],
        types: ["Object", "String", "Int32", "Int64", "Int16", "Byte", "Boolean", "Double", "Single", "Decimal", "Char", "DateTime", "TimeSpan", "Guid", "List", "Dictionary", "IEnumerable", "IList", "IDictionary", "Task", "ValueTask", "Action", "Func", "Exception", "Console", "Math", "StringBuilder", "HashSet", "Span", "Memory", "Nullable", "Array", "Tuple", "CancellationToken", "IDisposable", "IAsyncEnumerable"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: cComments,
        strings: [
            StringRule(open: "\"\"\"", close: "\"\"\"", escape: false, multiline: true, prefixes: ["$", "$$"]),
            StringRule(open: "\"", close: "\"", escape: false, multiline: true, prefixes: ["@", "$@", "@$"]),
            StringRule(open: "\"", close: "\"", prefixes: ["$"]),
            StringRule(open: "'", close: "'", maxLength: 10),
        ],
        preprocessorPrefixes: ["#"],
        uppercaseIdentifiersAreTypes: true
    )

    static let java = Language(
        id: "java", name: "Java", extensions: ["java"],
        keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "default", "do", "double", "else", "enum", "extends", "final", "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int", "interface", "long", "native", "new", "package", "private", "protected", "public", "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "void", "volatile", "while", "var", "record", "sealed", "permits", "yield", "non-sealed"],
        types: ["String", "Object", "Integer", "Long", "Double", "Float", "Boolean", "Character", "Byte", "Short", "List", "Map", "Set", "ArrayList", "HashMap", "HashSet", "Optional", "Stream", "Exception", "RuntimeException", "Thread", "Runnable", "StringBuilder", "System", "Math"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: cComments,
        strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true)] + cStrings,
        annotationPrefixes: ["@"],
        uppercaseIdentifiersAreTypes: true
    )

    static let kotlin = Language(
        id: "kotlin", name: "Kotlin", extensions: ["kt", "kts"],
        keywords: ["as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "typeof", "val", "var", "when", "while", "by", "catch", "constructor", "delegate", "dynamic", "field", "file", "finally", "get", "import", "init", "param", "property", "receiver", "set", "setparam", "value", "where", "abstract", "actual", "annotation", "companion", "const", "crossinline", "data", "enum", "expect", "external", "final", "infix", "inline", "inner", "internal", "lateinit", "noinline", "open", "operator", "out", "override", "private", "protected", "public", "reified", "sealed", "suspend", "tailrec", "vararg", "it"],
        types: ["Int", "Long", "Short", "Byte", "Double", "Float", "Boolean", "Char", "String", "Unit", "Nothing", "Any", "List", "MutableList", "Map", "MutableMap", "Set", "MutableSet", "Array", "Pair", "Triple", "Sequence", "Flow"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [BlockCommentRule(start: "/*", end: "*/", nested: true)],
        strings: [StringRule(open: "\"\"\"", close: "\"\"\"", escape: false, multiline: true)] + cStrings,
        annotationPrefixes: ["@"],
        uppercaseIdentifiersAreTypes: true
    )

    static let scala = Language(
        id: "scala", name: "Scala", extensions: ["scala", "sc"],
        keywords: ["abstract", "case", "catch", "class", "def", "do", "else", "enum", "export", "extends", "extension", "false", "final", "finally", "for", "forSome", "given", "if", "implicit", "import", "lazy", "match", "new", "null", "object", "override", "package", "private", "protected", "return", "sealed", "super", "then", "this", "throw", "trait", "true", "try", "type", "using", "val", "var", "while", "with", "yield", "derives", "inline", "opaque", "open", "transparent"],
        types: ["Int", "Long", "Double", "Float", "Boolean", "Char", "String", "Unit", "Any", "AnyRef", "Nothing", "Option", "Some", "None", "List", "Seq", "Map", "Set", "Vector", "Either", "Future", "Try"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [BlockCommentRule(start: "/*", end: "*/", nested: true)],
        strings: [StringRule(open: "\"\"\"", close: "\"\"\"", escape: false, multiline: true, prefixes: ["s", "f", "raw"]), StringRule(open: "\"", close: "\"", prefixes: ["s", "f", "raw"]), StringRule(open: "'", close: "'", maxLength: 8)],
        annotationPrefixes: ["@"],
        uppercaseIdentifiersAreTypes: true
    )

    static let go = Language(
        id: "go", name: "Go", extensions: ["go"],
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"],
        types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any", "comparable"],
        literals: ["true", "false", "nil", "iota"],
        lineComments: ["//"], blockComments: cComments,
        strings: [StringRule(open: "`", close: "`", escape: false, multiline: true)] + cStrings,
        uppercaseIdentifiersAreTypes: false
    )

    static let rust = Language(
        id: "rust", name: "Rust", extensions: ["rs"],
        keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while", "union", "macro_rules"],
        types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc", "HashMap", "HashSet", "BTreeMap", "Some", "None", "Ok", "Err", "Cow", "RefCell", "Cell", "Mutex"],
        literals: ["true", "false"],
        lineComments: ["//"], blockComments: [BlockCommentRule(start: "/*", end: "*/", nested: true)],
        strings: [
            StringRule(open: "r#\"", close: "\"#", escape: false, multiline: true),
            StringRule(open: "\"", close: "\"", multiline: true, prefixes: ["b"]),
            StringRule(open: "'", close: "'", maxLength: 12),
        ],
        annotationPrefixes: ["#[", "#!["],
        uppercaseIdentifiersAreTypes: true
    )

    static let dart = Language(
        id: "dart", name: "Dart", extensions: ["dart"],
        keywords: ["abstract", "as", "assert", "async", "await", "base", "break", "case", "catch", "class", "const", "continue", "covariant", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external", "factory", "false", "final", "finally", "for", "Function", "get", "hide", "if", "implements", "import", "in", "interface", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required", "rethrow", "return", "sealed", "set", "show", "static", "super", "switch", "sync", "this", "throw", "true", "try", "typedef", "var", "void", "when", "while", "with", "yield"],
        types: ["int", "double", "num", "bool", "String", "List", "Map", "Set", "Future", "Stream", "Object", "Widget", "BuildContext", "Iterable", "Duration", "DateTime"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [BlockCommentRule(start: "/*", end: "*/", nested: true)],
        strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true, prefixes: ["r"]), StringRule(open: "'''", close: "'''", multiline: true, prefixes: ["r"]), StringRule(open: "\"", close: "\"", prefixes: ["r"]), StringRule(open: "'", close: "'", prefixes: ["r"])],
        annotationPrefixes: ["@"],
        uppercaseIdentifiersAreTypes: true
    )

    private static let jsKeywords: Set<String> = ["await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new", "return", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield", "async", "of", "get", "set", "from", "as"]
    private static let jsTypes: Set<String> = ["Array", "Object", "String", "Number", "Boolean", "Promise", "Map", "Set", "WeakMap", "Symbol", "Date", "RegExp", "Error", "JSON", "Math", "console", "document", "window", "Function", "BigInt"]
    private static let jsStrings: [StringRule] = [
        StringRule(open: "`", close: "`", multiline: true),
        StringRule(open: "\"", close: "\""),
        StringRule(open: "'", close: "'"),
    ]

    static let javascript = Language(
        id: "javascript", name: "JavaScript", extensions: ["js", "jsx", "mjs", "cjs"],
        keywords: jsKeywords, types: jsTypes,
        literals: ["true", "false", "null", "undefined", "NaN", "Infinity"],
        lineComments: ["//"], blockComments: cComments, strings: jsStrings,
        identifierChars: "$",
        annotationPrefixes: ["@"]
    )

    static let typescript = Language(
        id: "typescript", name: "TypeScript", extensions: ["ts", "tsx", "mts", "cts"],
        keywords: jsKeywords.union(["abstract", "any", "boolean", "constructor", "declare", "implements", "interface", "is", "keyof", "module", "namespace", "never", "number", "object", "override", "private", "protected", "public", "readonly", "require", "string", "symbol", "type", "unknown", "unique", "infer", "satisfies", "asserts", "out", "accessor"]),
        types: jsTypes.union(["Record", "Partial", "Required", "Readonly", "Pick", "Omit", "Exclude", "Extract", "NonNullable", "ReturnType", "Parameters", "Awaited"]),
        literals: ["true", "false", "null", "undefined", "NaN", "Infinity"],
        lineComments: ["//"], blockComments: cComments, strings: jsStrings,
        identifierChars: "$",
        annotationPrefixes: ["@"],
        uppercaseIdentifiersAreTypes: true
    )

    static let python = Language(
        id: "python", name: "Python", extensions: ["py", "pyw", "pyi"],
        fileNames: ["SConstruct", "SConscript"],
        keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case", "self", "cls"],
        types: ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "bytes", "object", "type", "Exception", "ValueError", "TypeError", "KeyError", "RuntimeError", "range", "print", "len", "super", "isinstance", "enumerate", "zip", "map", "filter", "sorted", "open", "Optional", "List", "Dict", "Any", "Union", "Callable"],
        literals: ["True", "False", "None"],
        lineComments: ["#"],
        strings: [
            StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true, prefixes: ["f", "r", "b", "u", "rb", "br", "fr", "rf"]),
            StringRule(open: "'''", close: "'''", multiline: true, prefixes: ["f", "r", "b", "u", "rb", "br", "fr", "rf"]),
            StringRule(open: "\"", close: "\"", prefixes: ["f", "r", "b", "u", "rb", "br", "fr", "rf"]),
            StringRule(open: "'", close: "'", prefixes: ["f", "r", "b", "u", "rb", "br", "fr", "rf"]),
        ],
        annotationPrefixes: ["@"]
    )

    static let ruby = Language(
        id: "ruby", name: "Ruby", extensions: ["rb", "rake", "gemspec", "ru"],
        fileNames: ["Gemfile", "Rakefile", "Podfile", "Fastfile", "Brewfile"],
        keywords: ["alias", "and", "begin", "BEGIN", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "END", "ensure", "for", "if", "in", "module", "next", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "undef", "unless", "until", "when", "while", "yield", "require", "require_relative", "include", "extend", "attr_accessor", "attr_reader", "attr_writer", "private", "public", "protected", "raise", "lambda", "proc", "puts", "print", "new"],
        types: ["String", "Integer", "Float", "Array", "Hash", "Symbol", "Proc", "Object", "Kernel", "Module", "Class", "Struct", "Time", "File", "IO", "Range", "Regexp", "Exception", "StandardError"],
        literals: ["true", "false", "nil"],
        lineComments: ["#"],
        blockComments: [BlockCommentRule(start: "=begin", end: "=end")],
        strings: [StringRule(open: "\"", close: "\"", multiline: true), StringRule(open: "'", close: "'", multiline: true), StringRule(open: "%w[", close: "]", escape: false), StringRule(open: "%i[", close: "]", escape: false)],
        identifierChars: "?!",
        annotationPrefixes: [],
        variablePrefixes: ["@@", "@", "$"],
        uppercaseIdentifiersAreTypes: true
    )

    static let php = Language(
        id: "php", name: "PHP", extensions: ["php", "phtml", "php5"],
        keywords: ["abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "enum", "extends", "final", "finally", "fn", "for", "foreach", "function", "global", "goto", "if", "implements", "include", "include_once", "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace", "new", "or", "print", "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch", "throw", "trait", "try", "unset", "use", "var", "while", "xor", "yield", "self", "parent"],
        types: ["int", "float", "string", "bool", "array", "object", "mixed", "void", "null", "iterable", "never", "Exception", "Closure", "Generator", "Throwable", "DateTime", "PDO"],
        literals: ["true", "false", "null", "TRUE", "FALSE", "NULL"],
        lineComments: ["//", "#"], blockComments: cComments,
        strings: [StringRule(open: "\"", close: "\"", multiline: true), StringRule(open: "'", close: "'", multiline: true)],
        annotationPrefixes: ["#["],
        variablePrefixes: ["$"],
        uppercaseIdentifiersAreTypes: true
    )

    static let perl = Language(
        id: "perl", name: "Perl", extensions: ["pl", "pm", "t"],
        keywords: ["my", "our", "local", "sub", "if", "elsif", "else", "unless", "while", "until", "for", "foreach", "do", "last", "next", "redo", "return", "use", "no", "package", "require", "print", "printf", "say", "die", "warn", "eval", "defined", "undef", "shift", "unshift", "push", "pop", "splice", "scalar", "ref", "bless", "wantarray", "and", "or", "not", "xor", "eq", "ne", "lt", "gt", "le", "ge", "cmp", "x", "qw", "strict", "warnings", "BEGIN", "END", "open", "close", "chomp", "split", "join", "map", "grep", "sort", "keys", "values", "each", "exists", "delete"],
        literals: [],
        lineComments: ["#"],
        blockComments: [BlockCommentRule(start: "=pod", end: "=cut"), BlockCommentRule(start: "=head1", end: "=cut")],
        strings: [StringRule(open: "\"", close: "\"", multiline: true), StringRule(open: "'", close: "'", multiline: true)],
        variablePrefixes: ["$", "@", "%"]
    )

    static let lua = Language(
        id: "lua", name: "Lua", extensions: ["lua"],
        keywords: ["and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if", "in", "local", "not", "or", "repeat", "return", "then", "until", "while", "self"],
        types: ["string", "table", "math", "io", "os", "print", "pairs", "ipairs", "type", "tostring", "tonumber", "require", "setmetatable", "getmetatable", "coroutine", "error", "pcall", "assert"],
        literals: ["true", "false", "nil"],
        lineComments: ["--"],
        blockComments: [BlockCommentRule(start: "--[[", end: "]]"), BlockCommentRule(start: "--[==[", end: "]==]")],
        strings: [StringRule(open: "[[", close: "]]", escape: false, multiline: true), StringRule(open: "\"", close: "\""), StringRule(open: "'", close: "'")]
    )

    static let r = Language(
        id: "r", name: "R", extensions: ["r", "R", "rmd"],
        keywords: ["if", "else", "repeat", "while", "function", "for", "next", "break", "in", "library", "require", "return", "source", "TRUE", "FALSE", "NULL", "NA", "Inf", "NaN", "NA_integer_", "NA_real_", "NA_character_"],
        types: ["c", "list", "data.frame", "matrix", "vector", "factor", "print", "paste", "paste0", "length", "nrow", "ncol", "apply", "lapply", "sapply", "mean", "sum", "seq", "rep", "cat"],
        literals: ["TRUE", "FALSE", "NULL", "NA", "Inf", "NaN"],
        lineComments: ["#"],
        strings: [StringRule(open: "\"", close: "\"", multiline: true), StringRule(open: "'", close: "'", multiline: true)],
        identifierChars: "."
    )

    static let shell = Language(
        id: "shell", name: "Shell Script", extensions: ["sh", "bash", "zsh", "ksh", "fish", "command", "bashrc", "zshrc", "profile", "bash_profile", "zprofile"],
        fileNames: [".bashrc", ".zshrc", ".profile", ".bash_profile", ".zprofile", ".zshenv", ".bash_aliases", "PKGBUILD"],
        keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "select", "time", "return", "exit", "break", "continue", "local", "export", "declare", "readonly", "typeset", "unset", "shift", "source", "alias", "set", "trap", "eval", "exec", "let", "test", "coproc"],
        types: ["echo", "printf", "read", "cd", "pwd", "ls", "cat", "grep", "sed", "awk", "cut", "sort", "uniq", "tr", "find", "xargs", "mkdir", "rm", "cp", "mv", "chmod", "chown", "touch", "head", "tail", "wc", "tee", "curl", "wget", "tar", "gzip", "ssh", "scp", "git", "docker", "kubectl", "make", "sudo", "which", "type", "true", "false", "sleep", "kill", "ps", "env", "dirname", "basename", "date", "seq", "rsync", "jq", "npm", "python", "python3", "node", "swift", "xcodebuild"],
        literals: [],
        lineComments: ["#"],
        strings: [StringRule(open: "\"", close: "\"", multiline: true), StringRule(open: "'", close: "'", escape: false, multiline: true), StringRule(open: "$'", close: "'", multiline: true)],
        identifierChars: "-",
        variablePrefixes: ["$"]
    )

    static let powershell = Language(
        id: "powershell", name: "PowerShell", extensions: ["ps1", "psm1", "psd1"],
        keywords: ["begin", "break", "catch", "class", "continue", "data", "define", "do", "dynamicparam", "else", "elseif", "end", "enum", "exit", "filter", "finally", "for", "foreach", "from", "function", "hidden", "if", "in", "param", "process", "return", "static", "switch", "throw", "trap", "try", "until", "using", "var", "while", "workflow", "-eq", "-ne", "-gt", "-lt", "-ge", "-le", "-and", "-or", "-not", "-like", "-match", "-contains", "-in", "-is", "-as"],
        types: ["Write-Host", "Write-Output", "Get-ChildItem", "Get-Item", "Set-Item", "Get-Content", "Set-Content", "ForEach-Object", "Where-Object", "Select-Object", "Sort-Object", "New-Object", "Get-Process", "Invoke-RestMethod", "Invoke-WebRequest", "Import-Module", "Export-Csv", "Import-Csv", "ConvertTo-Json", "ConvertFrom-Json", "Test-Path", "Join-Path", "Out-File"],
        literals: ["$true", "$false", "$null"],
        lineComments: ["#"],
        blockComments: [BlockCommentRule(start: "<#", end: "#>")],
        strings: [StringRule(open: "@\"", close: "\"@", escape: false, multiline: true), StringRule(open: "@'", close: "'@", escape: false, multiline: true), StringRule(open: "\"", close: "\"", escape: false), StringRule(open: "'", close: "'", escape: false)],
        identifierChars: "-",
        caseInsensitiveKeywords: true,
        uppercaseIdentifiersAreTypes: false
    )

    static let sql = Language(
        id: "sql", name: "SQL", extensions: ["sql", "psql", "mysql", "sqlite", "ddl", "dml"],
        keywords: ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "view", "index", "drop", "alter", "add", "column", "primary", "key", "foreign", "references", "constraint", "unique", "not", "null", "default", "and", "or", "in", "is", "like", "ilike", "between", "exists", "case", "when", "then", "else", "end", "as", "join", "inner", "left", "right", "full", "outer", "cross", "on", "using", "group", "by", "order", "having", "limit", "offset", "asc", "desc", "distinct", "union", "all", "intersect", "except", "with", "recursive", "begin", "commit", "rollback", "transaction", "grant", "revoke", "truncate", "cascade", "if", "replace", "temporary", "temp", "function", "procedure", "returns", "return", "declare", "trigger", "before", "after", "each", "row", "execute", "explain", "analyze", "vacuum", "over", "partition", "window", "rows", "range", "unbounded", "preceding", "following", "current", "fetch", "first", "next", "only", "cast", "coalesce", "nullif", "count", "sum", "avg", "min", "max", "schema", "database", "materialized", "sequence", "type", "enum", "extension", "language", "returning", "conflict", "do", "nothing", "merge", "matched", "lateral", "natural", "any", "some", "top", "go", "print", "exec", "identity", "nvarchar", "varchar", "char", "text", "int", "integer", "bigint", "smallint", "tinyint", "decimal", "numeric", "float", "real", "double", "precision", "boolean", "bool", "date", "time", "timestamp", "timestamptz", "interval", "json", "jsonb", "uuid", "serial", "bigserial", "bytea", "blob", "money", "bit", "datetime", "datetime2"],
        literals: ["true", "false", "null"],
        lineComments: ["--"], blockComments: cComments,
        strings: [StringRule(open: "'", close: "'", escape: false, multiline: true), StringRule(open: "\"", close: "\"", escape: false), StringRule(open: "`", close: "`", escape: false), StringRule(open: "[", close: "]", escape: false)],
        variablePrefixes: ["@", ":"],
        caseInsensitiveKeywords: true
    )

    static let graphql = Language(
        id: "graphql", name: "GraphQL", extensions: ["graphql", "gql"],
        keywords: ["query", "mutation", "subscription", "fragment", "on", "type", "interface", "union", "enum", "input", "scalar", "schema", "extend", "directive", "implements", "repeatable"],
        types: ["Int", "Float", "String", "Boolean", "ID"],
        literals: ["true", "false", "null"],
        lineComments: ["#"],
        strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true), StringRule(open: "\"", close: "\"")],
        annotationPrefixes: ["@"],
        variablePrefixes: ["$"],
        uppercaseIdentifiersAreTypes: true
    )

    static let makefile = Language(
        id: "makefile", name: "Makefile", extensions: ["mk", "make"],
        fileNames: ["Makefile", "makefile", "GNUmakefile"],
        keywords: ["ifeq", "ifneq", "ifdef", "ifndef", "else", "endif", "include", "define", "endef", "export", "unexport", "override", "vpath", "all", "clean", "install", "test", "build", ".PHONY", ".DEFAULT", ".SUFFIXES"],
        types: ["shell", "wildcard", "patsubst", "subst", "foreach", "call", "eval", "filter", "filter-out", "sort", "dir", "notdir", "basename", "suffix", "addprefix", "addsuffix", "word", "words", "firstword", "lastword", "strip", "findstring", "if", "or", "and", "error", "warning", "info", "abspath", "realpath"],
        lineComments: ["#"],
        strings: [StringRule(open: "\"", close: "\""), StringRule(open: "'", close: "'")],
        identifierChars: ".-",
        variablePrefixes: ["$"]
    )

    static let dockerfile = Language(
        id: "dockerfile", name: "Dockerfile", extensions: ["dockerfile"],
        fileNames: ["Dockerfile", "Containerfile"],
        keywords: ["FROM", "RUN", "CMD", "LABEL", "MAINTAINER", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT", "VOLUME", "USER", "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK", "SHELL", "AS"],
        lineComments: ["#"],
        strings: [StringRule(open: "\"", close: "\""), StringRule(open: "'", close: "'", escape: false)],
        variablePrefixes: ["$"],
        caseInsensitiveKeywords: false
    )

    static let toml = Language(
        id: "toml", name: "TOML", extensions: ["toml"],
        fileNames: ["Cargo.lock", "Pipfile"],
        keywords: [],
        literals: ["true", "false", "inf", "nan"],
        lineComments: ["#"],
        strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true), StringRule(open: "'''", close: "'''", escape: false, multiline: true), StringRule(open: "\"", close: "\""), StringRule(open: "'", close: "'", escape: false), StringRule(open: "[", close: "]", escape: false)],
        identifierChars: "-."
    )

    static let ini = Language(
        id: "ini", name: "INI / Config", extensions: ["ini", "cfg", "conf", "env", "properties", "editorconfig", "gitconfig", "gitignore", "gitattributes", "npmrc", "dockerignore"],
        fileNames: [".gitignore", ".gitattributes", ".editorconfig", ".env", ".npmrc", ".dockerignore", ".gitconfig", ".gitmodules"],
        keywords: [],
        literals: ["true", "false", "yes", "no", "on", "off"],
        lineComments: ["#", ";"],
        strings: [StringRule(open: "\"", close: "\""), StringRule(open: "'", close: "'", escape: false), StringRule(open: "[", close: "]", escape: false)],
        identifierChars: "-."
    )

    static let json = Language(id: "json", name: "JSON", extensions: ["json", "jsonc", "json5", "geojson", "webmanifest", "jsonl", "ndjson"], fileNames: [".babelrc", ".eslintrc", ".prettierrc", "tsconfig.json"], scanner: .json)
    static let yaml = Language(id: "yaml", name: "YAML", extensions: ["yml", "yaml"], fileNames: [".clang-format", ".swiftlint.yml"], scanner: .yaml)
    static let html = Language(id: "html", name: "HTML", extensions: ["html", "htm", "xhtml", "vue", "svelte", "erb", "cshtml", "razor", "handlebars", "hbs", "ejs", "jsp"], scanner: .html)
    static let xml = Language(id: "xml", name: "XML", extensions: ["xml", "plist", "svg", "xsl", "xslt", "xsd", "storyboard", "xib", "csproj", "fsproj", "vbproj", "props", "targets", "sln", "nuspec", "pom", "xcscheme", "entitlements", "strings", "xaml", "wsdl", "rss", "atom", "opml", "gpx", "kml"], scanner: .html)
    static let css = Language(id: "css", name: "CSS", extensions: ["css", "scss", "sass", "less"], scanner: .css)

    // MARK: Registry

    static let all: [Language] = [
        plainText, markdown, csv, tsv,
        swift, objectiveC, c, cpp, csharp, java, kotlin, scala, go, rust, dart,
        javascript, typescript, python, ruby, php, perl, lua, r,
        shell, powershell, sql, graphql,
        html, xml, css, json, yaml, toml, ini, makefile, dockerfile,
    ]

    static let byID: [String: Language] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func language(id: String) -> Language? { byID[id] }

    /// Detects a language from the file name (exact matches first, then the extension).
    static func language(forFileName fileName: String) -> Language? {
        let name = (fileName as NSString).lastPathComponent
        for lang in all where lang.fileNames.contains(name) { return lang }
        let lower = name.lowercased()
        for lang in all where lang.fileNames.contains(where: { $0.lowercased() == lower }) { return lang }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        for lang in all where lang.extensions.contains(ext) { return lang }
        let lowerExt = ext.lowercased()
        for lang in all where lang.extensions.contains(lowerExt) { return lang }
        return nil
    }

    /// Detects a language from a shebang line such as `#!/usr/bin/env python3`.
    static func language(forShebang firstLine: Substring) -> Language? {
        guard firstLine.hasPrefix("#!") else { return nil }
        let line = firstLine.lowercased()
        let table: [(String, Language)] = [
            ("python", python), ("ruby", ruby), ("node", javascript), ("deno", typescript), ("bun", typescript),
            ("perl", perl), ("php", php), ("lua", lua), ("swift", swift), ("pwsh", powershell), ("rscript", r),
            ("bash", shell), ("zsh", shell), ("sh", shell), ("fish", shell), ("ksh", shell),
        ]
        for (needle, lang) in table where line.contains(needle) { return lang }
        return nil
    }
}
