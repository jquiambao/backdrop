#!/usr/bin/swift
//File: source/CommandLine/CommandLine.swift


/*
 * CommandLine.swift
 * Copyright (c) 2014 Ben Gollmer.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* Required for setlocale(3) */
@exported import Darwin

let ShortOptionPrefix = "-"
let LongOptionPrefix = "--"

/* Stop parsing arguments when an ArgumentStopper (--) is detected. This is a GNU getopt
 * convention; cf. https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html
 */
let ArgumentStopper = "--"

/* Allow arguments to be attached to flags when separated by this character.
 * --flag=argument is equivalent to --flag argument
 */
let ArgumentAttacher: Character = "="

/* An output stream to stderr; used by CommandLine.printUsage(). */
private struct StderrOutputStream: OutputStreamType {
  static let stream = StderrOutputStream()
  func write(s: String) {
    fputs(s, stderr)
  }
}

/**
 * The CommandLine class implements a command-line interface for your app.
 * 
 * To use it, define one or more Options (see Option.swift) and add them to your
 * CommandLine object, then invoke `parse()`. Each Option object will be populated with
 * the value given by the user.
 *
 * If any required options are missing or if an invalid value is found, `parse()` will throw
 * a `ParseError`. You can then call `printUsage()` to output an automatically-generated usage
 * message.
 */
public class CommandLine {
  private var _arguments: [String]
  private var _options: [Option] = [Option]()
  
  /** A ParseError is thrown if the `parse()` method fails. */
  public enum ParseError: ErrorType, CustomStringConvertible {
    /** Thrown if an unrecognized argument is passed to `parse()` in strict mode */
    case InvalidArgument(String)

    /** Thrown if the value for an Option is invalid (e.g. a string is passed to an IntOption) */
    case InvalidValueForOption(Option, [String])
    
    /** Thrown if an Option with required: true is missing */
    case MissingRequiredOptions([Option])
    
    public var description: String {
      switch self {
      case let .InvalidArgument(arg):
        return "Invalid argument: \(arg)"
      case let .InvalidValueForOption(opt, vals):
        let vs = vals.joinWithSeparator(", ")
        return "Invalid value(s) for option \(opt.flagDescription): \(vs)"
      case let .MissingRequiredOptions(opts):
        return "Missing required options: \(opts.map { return $0.flagDescription })"
      }
    }
  }
  
  /**
   * Initializes a CommandLine object.
   *
   * - parameter arguments: Arguments to parse. If omitted, the arguments passed to the app
   *   on the command line will automatically be used.
   *
   * - returns: An initalized CommandLine object.
   */
  public init(arguments: [String] = Process.arguments) {
    self._arguments = arguments
    
    /* Initialize locale settings from the environment */
    setlocale(LC_ALL, "")
  }
  
  /* Returns all argument values from flagIndex to the next flag or the end of the argument array. */
  private func _getFlagValues(flagIndex: Int) -> [String] {
    var args: [String] = [String]()
    var skipFlagChecks = false
    
    /* Grab attached arg, if any */
    var attachedArg = _arguments[flagIndex].splitByCharacter(ArgumentAttacher, maxSplits: 1)
    if attachedArg.count > 1 {
      args.append(attachedArg[1])
    }
    
    for var i = flagIndex + 1; i < _arguments.count; i++ {
      if !skipFlagChecks {
        if _arguments[i] == ArgumentStopper {
          skipFlagChecks = true
          continue
        }
        
        if _arguments[i].hasPrefix(ShortOptionPrefix) && Int(_arguments[i]) == nil &&
          _arguments[i].toDouble() == nil {
          break
        }
      }
    
      args.append(_arguments[i])
    }
    
    return args
  }
  
  /**
   * Adds an Option to the command line.
   *
   * - parameter option: The option to add.
   */
  public func addOption(option: Option) {
    _options.append(option)
  }
  
  /**
   * Adds one or more Options to the command line.
   *
   * - parameter options: An array containing the options to add.
   */
  public func addOptions(options: [Option]) {
    _options += options
  }
  
  /**
   * Adds one or more Options to the command line.
   *
   * - parameter options: The options to add.
   */
  public func addOptions(options: Option...) {
    _options += options
  }
  
  /**
   * Sets the command line Options. Any existing options will be overwritten.
   *
   * - parameter options: An array containing the options to set.
   */
  public func setOptions(options: [Option]) {
    _options = options
  }
  
  /**
   * Sets the command line Options. Any existing options will be overwritten.
   *
   * - parameter options: The options to set.
   */
  public func setOptions(options: Option...) {
    _options = options
  }
  
  /**
   * Parses command-line arguments into their matching Option values. Throws `ParseError` if
   * argument parsing fails.
   *
   * - parameter strict: Fail if any unrecognized arguments are present (default: false).
   */
  public func parse(strict: Bool = false) throws {
    for (idx, arg) in _arguments.enumerate() {
      if arg == ArgumentStopper {
        break
      }
      
      if !arg.hasPrefix(ShortOptionPrefix) {
        continue
      }
      
      let skipChars = arg.hasPrefix(LongOptionPrefix) ?
        LongOptionPrefix.characters.count : ShortOptionPrefix.characters.count
      let flagWithArg = arg[Range(start: arg.startIndex.advancedBy(skipChars), end: arg.endIndex)]
      
      /* The argument contained nothing but ShortOptionPrefix or LongOptionPrefix */
      if flagWithArg.isEmpty {
        continue
      }
      
      /* Remove attached argument from flag */
      let flag = flagWithArg.splitByCharacter(ArgumentAttacher, maxSplits: 1)[0]
      
      var flagMatched = false
      for option in _options where option.flagMatch(flag) {
        let vals = self._getFlagValues(idx)
        guard option.setValue(vals) else {
          throw ParseError.InvalidValueForOption(option, vals)
        }
          
        flagMatched = true
        break
      }
      
      /* Flags that do not take any arguments can be concatenated */
      let flagLength = flag.characters.count
      if !flagMatched && !arg.hasPrefix(LongOptionPrefix) {
        for (i, c) in flag.characters.enumerate() {
          for option in _options where option.flagMatch(String(c)) {
            /* Values are allowed at the end of the concatenated flags, e.g.
            * -xvf <file1> <file2>
            */
            let vals = (i == flagLength - 1) ? self._getFlagValues(idx) : [String]()
            guard option.setValue(vals) else {
              throw ParseError.InvalidValueForOption(option, vals)
            }
            
            flagMatched = true
            break
          }
        }
      }

      /* Invalid flag */
      guard !strict || flagMatched else {
        throw ParseError.InvalidArgument(arg)
      }
    }

    /* Check to see if any required options were not matched */
    let missingOptions = _options.filter { $0.required && !$0.wasSet }
    guard missingOptions.count == 0 else {
      throw ParseError.MissingRequiredOptions(missingOptions)
    }
  }
  
  /* printUsage() is generic for OutputStreamType because the Swift compiler crashes
   * on inout protocol function parameters in Xcode 7 beta 1 (rdar://21372694).
   */
  
  /**
   * Prints a usage message.
   * 
   * - parameter to: An OutputStreamType to write the error message to.
   */
  public func printUsage<TargetStream: OutputStreamType>(inout to: TargetStream) {
    let name = _arguments[0]
    
    var flagWidth = 0
    for opt in _options {
      flagWidth = max(flagWidth, "  \(opt.flagDescription):".characters.count)
    }

    print("Usage: \(name) [options]", toStream: &to)
    for opt in _options {
      let flags = "  \(opt.flagDescription):".paddedToWidth(flagWidth)
      print("\(flags)\n      \(opt.helpMessage)", toStream: &to)
    }
  }
  
  /**
   * Prints a usage message.
   *
   * - parameter error: An error thrown from `parse()`. A description of the error
   *   (e.g. "Missing required option --extract") will be printed before the usage message.
   * - parameter to: An OutputStreamType to write the error message to.
   */
  public func printUsage<TargetStream: OutputStreamType>(error: ErrorType, inout to: TargetStream) {
    print("\(error)\n", toStream: &to)
    printUsage(&to)
  }
  
  /**
   * Prints a usage message.
   *
   * - parameter error: An error thrown from `parse()`. A description of the error
   *   (e.g. "Missing required option --extract") will be printed before the usage message.
   */
  public func printUsage(error: ErrorType) {
    var out = StderrOutputStream.stream
    printUsage(error, to: &out)
  }
  
  /**
   * Prints a usage message.
   */
  public func printUsage() {
    var out = StderrOutputStream.stream
    printUsage(&out)
  }
}




//File: source/CommandLine/Option.swift


/*
 * Option.swift
 * Copyright (c) 2014 Ben Gollmer.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * The base class for a command-line option.
 */
public class Option {
  public let shortFlag: String?
  public let longFlag: String?
  public let required: Bool
  public let helpMessage: String
  
  /** True if the option was set when parsing command-line arguments */
  public var wasSet: Bool {
    return false
  }
  
  public var flagDescription: String {
    switch (shortFlag, longFlag) {
    case (let sf, let lf) where sf != nil && lf != nil:
      return "\(ShortOptionPrefix)\(sf!), \(LongOptionPrefix)\(lf!)"
    case (_, let lf) where lf != nil:
      return "\(LongOptionPrefix)\(lf!)"
    default:
      return "\(ShortOptionPrefix)\(shortFlag!)"
    }
  }
  
  private init(_ shortFlag: String?, _ longFlag: String?, _ required: Bool, _ helpMessage: String) {
    if let sf = shortFlag {
      assert(sf.characters.count == 1, "Short flag must be a single character")
      assert(Int(sf) == nil && sf.toDouble() == nil, "Short flag cannot be a numeric value")
    }
    
    if let lf = longFlag {
      assert(Int(lf) == nil && lf.toDouble() == nil, "Long flag cannot be a numeric value")
    }
    
    self.shortFlag = shortFlag
    self.longFlag = longFlag
    self.helpMessage = helpMessage
    self.required = required
  }
  
  /* The optional casts in these initalizers force them to call the private initializer. Without
   * the casts, they recursively call themselves.
   */
  
  /** Initializes a new Option that has both long and short flags. */
  public convenience init(shortFlag: String, longFlag: String, required: Bool = false, helpMessage: String) {
    self.init(shortFlag as String?, longFlag, required, helpMessage)
  }
  
  /** Initializes a new Option that has only a short flag. */
  public convenience init(shortFlag: String, required: Bool = false, helpMessage: String) {
    self.init(shortFlag as String?, nil, required, helpMessage)
  }
  
  /** Initializes a new Option that has only a long flag. */
  public convenience init(longFlag: String, required: Bool = false, helpMessage: String) {
    self.init(nil, longFlag as String?, required, helpMessage)
  }
  
  func flagMatch(flag: String) -> Bool {
    return flag == shortFlag || flag == longFlag
  }
  
  func setValue(values: [String]) -> Bool {
    return false
  }
}

/**
 * A boolean option. The presence of either the short or long flag will set the value to true;
 * absence of the flag(s) is equivalent to false.
 */
public class BoolOption: Option {
  private var _value: Bool = false
  
  public var value: Bool {
    return _value
  }
  
  override public var wasSet: Bool {
    return _value
  }
  
  override func setValue(values: [String]) -> Bool {
    _value = true
    return true
  }
}

/**  An option that accepts a positive or negative integer value. */
public class IntOption: Option {
  private var _value: Int?
  
  public var value: Int? {
    return _value
  }
  
  override public var wasSet: Bool {
    return _value != nil
  }

  override func setValue(values: [String]) -> Bool {
    if values.count == 0 {
      return false
    }
    
    if let val = Int(values[0]) {
      _value = val
      return true
    }
    
    return false
  }
}

/**
 * An option that represents an integer counter. Each time the short or long flag is found
 * on the command-line, the counter will be incremented.
 */
public class CounterOption: Option {
  private var _value: Int = 0
  
  public var value: Int {
    return _value
  }
  
  override public var wasSet: Bool {
    return _value > 0
  }
  
  override func setValue(values: [String]) -> Bool {
    _value += 1
    return true
  }
}

/**  An option that accepts a positive or negative floating-point value. */
public class DoubleOption: Option {
  private var _value: Double?
  
  public var value: Double? {
    return _value
  }

  override public var wasSet: Bool {
    return _value != nil
  }
  
  override func setValue(values: [String]) -> Bool {
    if values.count == 0 {
      return false
    }
    
    if let val = values[0].toDouble() {
      _value = val
      return true
    }
    
    return false
  }
}

/**  An option that accepts a string value. */
public class StringOption: Option {
  private var _value: String? = nil
  
  public var value: String? {
    return _value
  }
  
  override public var wasSet: Bool {
    return _value != nil
  }
  
  override func setValue(values: [String]) -> Bool {
    if values.count == 0 {
      return false
    }
    
    _value = values[0]
    return true
  }
}

/**  An option that accepts one or more string values. */
public class MultiStringOption: Option {
  private var _value: [String]?
  
  public var value: [String]? {
    return _value
  }
  
  override public var wasSet: Bool {
    return _value != nil
  }
  
  override func setValue(values: [String]) -> Bool {
    if values.count == 0 {
      return false
    }
    
    _value = values
    return true
  }
}

/** An option that represents an enum value. */
public class EnumOption<T:RawRepresentable where T.RawValue == String>: Option {
  private var _value: T?
  public var value: T? {
    return _value
  }
  
  override public var wasSet: Bool {
    return _value != nil
  }
  
  /* Re-defining the intializers is necessary to make the Swift 2 compiler happy, as
   * of Xcode 7 beta 2.
   */
  
  private override init(_ shortFlag: String?, _ longFlag: String?, _ required: Bool, _ helpMessage: String) {
    super.init(shortFlag, longFlag, required, helpMessage)
  }
  
  /** Initializes a new Option that has both long and short flags. */
  public convenience init(shortFlag: String, longFlag: String, required: Bool = false, helpMessage: String) {
    self.init(shortFlag as String?, longFlag, required, helpMessage)
  }
  
  /** Initializes a new Option that has only a short flag. */
  public convenience init(shortFlag: String, required: Bool = false, helpMessage: String) {
    self.init(shortFlag as String?, nil, required, helpMessage)
  }
  
  /** Initializes a new Option that has only a long flag. */
  public convenience init(longFlag: String, required: Bool = false, helpMessage: String) {
    self.init(nil, longFlag as String?, required, helpMessage)
  }
  
  override func setValue(values: [String]) -> Bool {
    if values.count == 0 {
      return false
    }
    
    if let v = T(rawValue: values[0]) {
      _value = v
      return true
    }
    
    return false
  }
}




//File: source/CommandLine/StringExtensions.swift


/*
 * StringExtensions.swift
 * Copyright (c) 2014 Ben Gollmer.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* Required for localeconv(3) */
import Darwin

internal extension String {
  /* Retrieves locale-specified decimal separator from the environment
   * using localeconv(3).
   */
  private func _localDecimalPoint() -> Character {
    let locale = localeconv()
    if locale != nil {
      let decimalPoint = locale.memory.decimal_point
      if decimalPoint != nil {
        return Character(UnicodeScalar(UInt32(decimalPoint.memory)))
      }
    }
    
    return "."
  }
  
  /**
   * Attempts to parse the string value into a Double.
   *
   * - returns: A Double if the string can be parsed, nil otherwise.
   */
  func toDouble() -> Double? {
    var characteristic: String = "0"
    var mantissa: String = "0"
    var inMantissa: Bool = false
    var isNegative: Bool = false
    let decimalPoint = self._localDecimalPoint()
    
    for (i, c) in self.characters.enumerate() {
      if i == 0 && c == "-" {
        isNegative = true
        continue
      }
      
      if c == decimalPoint {
        inMantissa = true
        continue
      }
      
      if Int(String(c)) != nil {
        if !inMantissa {
          characteristic.append(c)
        } else {
          mantissa.append(c)
        }
      } else {
        /* Non-numeric character found, bail */
        return nil
      }
    }
    
    return (Double(Int(characteristic)!) +
      Double(Int(mantissa)!) / pow(Double(10), Double(mantissa.characters.count - 1))) *
      (isNegative ? -1 : 1)
  }
  
  /**
   * Splits a string into an array of string components.
   *
   * - parameter splitBy:  The character to split on.
   * - parameter maxSplit: The maximum number of splits to perform. If 0, all possible splits are made.
   *
   * - returns: An array of string components.
   */
  func splitByCharacter(splitBy: Character, maxSplits: Int = 0) -> [String] {
    var s = [String]()
    var numSplits = 0
    
    var curIdx = self.startIndex
    for(var i = self.startIndex; i != self.endIndex; i = i.successor()) {
      let c = self[i]
      if c == splitBy && (maxSplits == 0 || numSplits < maxSplits) {
        s.append(self[Range(start: curIdx, end: i)])
        curIdx = i.successor()
        numSplits++
      }
    }
    
    if curIdx != self.endIndex {
      s.append(self[Range(start: curIdx, end: self.endIndex)])
    }
    
    return s
  }
  
  /**
   * Pads a string to the specified width.
   * 
   * - parameter width: The width to pad the string to.
   * - parameter padBy: The character to use for padding.
   *
   * - returns: A new string, padded to the given width.
   */
  func paddedToWidth(width: Int, padBy: Character = " ") -> String {
    var s = self
    var currentLength = self.characters.count
    
    while currentLength++ < width {
      s.append(padBy)
    }
    
    return s
  }
  
  /**
   * Wraps a string to the specified width.
   * 
   * This just does simple greedy word-packing, it doesn't go full Knuth-Plass.
   * If a single word is longer than the line width, it will be placed (unsplit)
   * on a line by itself.
   *
   * - parameter width:   The maximum length of a line.
   * - parameter wrapBy:  The line break character to use.
   * - parameter splitBy: The character to use when splitting the string into words.
   *
   * - returns: A new string, wrapped at the given width.
   */
  func wrappedAtWidth(width: Int, wrapBy: Character = "\n", splitBy: Character = " ") -> String {
    var s = ""
    var currentLineWidth = 0
    
    for word in self.splitByCharacter(splitBy) {
      let wordLength = word.characters.count
      
      if currentLineWidth + wordLength + 1 > width {
        /* Word length is greater than line length, can't wrap */
        if wordLength >= width {
          s += word
        }
        
        s.append(wrapBy)
        currentLineWidth = 0
      }
      
      currentLineWidth += wordLength + 1
      s += word
      s.append(splitBy)
    }
    
    return s
  }
}




//File: source/Utils/DateUtils.swift


import Foundation

public func CurrentDateatMidnightGMT() -> NSDate! {
    let calendar = NSCalendar.currentCalendar()
    calendar.timeZone = NSTimeZone(name: "GMT")!
    let components = calendar.components([.Year, .Month, .Day], fromDate: NSDate())
    let midnight = calendar.dateFromComponents(components)
    return midnight!
}






//File: source/BuildNumberManager.swift


import Foundation

public class BuildNumberManager {

    private(set) public var startDate: NSDate!
    private(set) public var appName: String!
    private(set) public var envName: String!

    //-------------------------------------------------------------------------------------------
    // MARK: Initialization & Destruction
    //-------------------------------------------------------------------------------------------

    public init(startDate: NSDate!, appName: String!, envName: String!) {
        self.startDate = startDate
        self.appName = appName
        self.envName = envName
    }

    //-------------------------------------------------------------------------------------------
    // MARK: Public Methods
    //-------------------------------------------------------------------------------------------

    public func currentBuildNumber() -> String! {
        if (NSFileManager.defaultManager().fileExistsAtPath(self.buildFilePath()) == false) {
            self.writeBuildNumber("0.0.0")
        }
        let currentBuild: NSString = try! NSString(contentsOfFile: self.buildFilePath(),
                encoding: NSUTF8StringEncoding)
        return currentBuild as String
    }

    public func incrementBuildNumber() {

        let components: NSArray = self.currentBuildNumber().componentsSeparatedByString(".")
        let daysElapsed = self.daysElapsed()

        let week: Int! = daysElapsed / 7
        let day: Int! = (daysElapsed % 7)

//        println("Days elapsed: \(daysElapsed), Week: \(week), day: \(day)")

        let buildDay: Int = (components[1] as! NSString).integerValue
        var count: Int = (components[2] as! NSString).integerValue

        if (buildDay != day) {
            count = 0
        } else {
            count++
        }

        var version = String(week)
        version += "."
        version += String(day)
        version += "."
        version += String(count)

        self.writeBuildNumber(version)
    }

    //-------------------------------------------------------------------------------------------
    // MARK: Private Methods
    //-------------------------------------------------------------------------------------------

    private func daysElapsed() -> Int! {

        let endDate = CurrentDateatMidnightGMT()

        let cal = NSCalendar.currentCalendar()
        let unit: NSCalendarUnit = .Day

        let components = cal.components(unit, fromDate: self.startDate, toDate: endDate, options: [])
        let days = components.day
        return days
    }

    private func buildFilePath() -> String! {
        let fileName = "\(self.appName)_\(self.envName).build"
        return ".buildNumbers/\(fileName)"
    }

    private func writeBuildNumber(number: String) {
        do {
            try NSFileManager.defaultManager().createDirectoryAtPath(".buildNumbers",
                    withIntermediateDirectories: true, attributes: nil)
        } catch _ {
        }
        do {
            try number.writeToFile(self.buildFilePath(), atomically: true, encoding: NSUTF8StringEncoding)
        } catch _ {
        }
    }

}




//File: source/Configurer.swift


import Foundation

public class Configurer {

    private(set) public var envFile: EnvFile!
    private(set) public var selectedEnv: Environment!
    private(set) public var increment: Bool!
    private var plist: NSMutableDictionary!
    private var buildNumberManager: BuildNumberManager!

    //-------------------------------------------------------------------------------------------
    // MARK: Initialization & Destruction
    //-------------------------------------------------------------------------------------------

    public init(envFile: EnvFile!, selectedEnv: Environment?, increment: Bool!) {
        self.envFile = envFile

        let fileManager = NSFileManager.defaultManager()
        let plistPath = fileManager.currentDirectoryPath + "/" + envFile.infoPlistRelativePath
        if (!fileManager.fileExistsAtPath(plistPath)) {
            NSException(name: NSInternalInconsistencyException, reason:
            "EnvFile specifies plist at path: " + plistPath + ", but this file does not exist.", userInfo: nil).raise()
        }

        self.plist = NSMutableDictionary(contentsOfFile: plistPath)!

        if (selectedEnv == nil) {
            if (plist.valueForKey("SelectedEnv") != nil) {
                let envName = plist.valueForKey("SelectedEnv") as! String!
                let env = envFile.environmentWithName(envName);
                if (env != nil) {
                    self.selectedEnv = env!
                } else {
                    NSException(name: NSInternalInconsistencyException, reason:
                    "Can't infer selected environment from Info.plist. Either it is not specified or does not match " +
                            "any enviroments in EnvFile.plist", userInfo: nil).raise()
                }
            } else {
                NSException(name: NSInternalInconsistencyException, reason:
                "Can't infer selected environment from Info.plist, because there is no value for key 'SelectedEnv", userInfo: nil).raise()
            }
        } else {
            self.selectedEnv = selectedEnv
        }

        self.increment = increment
        self.buildNumberManager = BuildNumberManager(startDate: envFile.createdDate, appName: envFile.projectName,
                envName: self.selectedEnv.name)
    }

    //-------------------------------------------------------------------------------------------
    // MARK: Public Methods
    //-------------------------------------------------------------------------------------------

    public func printInfo() {
        print("\nEnvironment:\t\(self.selectedEnv.name)")
        print("Build:\t\t\(self.buildNumberManager.currentBuildNumber())")
    }

    public func configure() {

        if (self.increment == true) {
            self.incrementBuildNumber();
        }

        self.configureForEnvironment()
        self.save()
    }

    //-------------------------------------------------------------------------------------------
    // MARK: Private Methods
    //-------------------------------------------------------------------------------------------

    private func incrementBuildNumber() {
        buildNumberManager.incrementBuildNumber()
        self.plist["CFBundleVersion"] = buildNumberManager.currentBuildNumber()
    }

    private func configureForEnvironment() {
        for (key, values) in self.selectedEnv.configs {
            self.plist[key] = values
        }
        self.plist["SelectedEnv"] = selectedEnv.name
    }

    private func save() {
        self.plist.writeToFile(envFile.infoPlistRelativePath, atomically: true)
    }

}



//File: source/EnvFile.swift


import Foundation

public class EnvFile {


    public var infoPlistRelativePath: String! {
        get {
            return storage["InfoPlist"] as! String!
        }
        set {
            storage["InfoPlist"] = newValue
        }
    }

    public var projectName: String! {
        get {
            return storage["ProjectName"] as! String!
        }
        set {
            storage["ProjectName"] = newValue
        }
    }

    public var createdDate: NSDate! {
        get {
            return storage["CreatedDate"] as! NSDate!
        }
        set {
            storage["CreatedDate"] = newValue
        }
    }

    private (set) public var envFilePath: String!
    private var storage: Dictionary<String, AnyObject>

    //-------------------------------------------------------------------------------------------
    // MARK: Initialization & Destruction
    //-------------------------------------------------------------------------------------------

    public init(envFilePath: String!, infoPlistPath: String?, projectName: String?) {
        self.envFilePath = envFilePath
        self.storage = Dictionary()
        self.createdDate = CurrentDateatMidnightGMT()

        let fileManager = NSFileManager.defaultManager()
        if (fileManager.fileExistsAtPath(self.envFilePath)) {
            let dictionary = NSDictionary(contentsOfFile: envFilePath)
            if (dictionary != nil) {
                self.storage = dictionary as! Dictionary<String, AnyObject>
            }
            else {
                NSException(name: NSInternalInconsistencyException, reason:
                "The file \(envFilePath) is not a valid EnvFile", userInfo: nil).raise()
            }

        } else if (infoPlistPath != nil && projectName != nil) {
            self.infoPlistRelativePath = infoPlistPath!
            self.projectName = projectName!
        } else {
            NSException(name: NSInternalInconsistencyException, reason:
            "Can't create new EnvFile without specifying project name and Info.plist path", userInfo: nil).raise()
        }
    }

    public convenience init(envFilePath: String!) {
        self.init(envFilePath: envFilePath, infoPlistPath: nil, projectName: nil)
    }

    //-------------------------------------------------------------------------------------------
    // MARK: Public Methods
    //-------------------------------------------------------------------------------------------

    public func environmentWithName(name: String!) -> Environment? {
        for environment in self.environments() {
            if (environment.name == name) {
                return environment
            }
        }
        return nil;
    }

    public func environments() -> Array<Environment> {
        var environments = Array<Environment>()

        if (self.storage["environments"] != nil) {
            let plistEnvs = self.storage["environments"] as! Dictionary<String, AnyObject>
            for (key, values) in plistEnvs {
                let environment = Environment(name: key)
                environment.addAll(values as! Dictionary<String, AnyObject>)

                environments.append(environment)
            }
        }
        return environments
    }

    public func add(environment: Environment) {
        let configs = environment.configs as NSDictionary
        if (self.storage["environments"] == nil) {
            self.storage["environments"] = Dictionary<String, AnyObject>()
        }
        let environments = self.storage["environments"] as! NSDictionary
        environments.setValue(configs, forKey: environment.name)
    }

    //-------------------------------------------------------------------------------------------
    // MARK: Private Methods
    //-------------------------------------------------------------------------------------------

    private func save() {
        let dictionary = self.storage as NSDictionary
        dictionary.writeToFile(self.envFilePath, atomically: true)
    }
}




//File: source/Environment.swift


import Foundation

public class Environment {

    private(set) public var name: String!
    private(set) public var configs: Dictionary<String, AnyObject>!

    public init(name: String!) {
        self.name = name;
        self.configs = Dictionary()
    }

    public func setConfig(config: AnyObject!, forKey: String!) {
        self.configs[forKey] = config
    }

    public func addAll(properties: Dictionary<String, AnyObject>!) {
        for (key, value) in properties {
            self.setConfig(value, forKey: key)
        }
    }




}




//File: source/Main/main.swift


import Foundation

let cli = CommandLine()

let filePath = StringOption(shortFlag: "e", longFlag: "envFile", required: false,
        helpMessage: "Custom EnvFile to use.")
let newVersion = BoolOption(shortFlag: "n", longFlag: "newVersion",
        helpMessage: "Increments the build number.")
let select = StringOption(shortFlag: "s", longFlag: "select",
        helpMessage: "Name of config specified in EnvFile to use.")
let help = BoolOption(shortFlag: "h", longFlag: "help",
        helpMessage: "Prints this message.")

cli.addOptions(filePath, newVersion, select, help)

do {
    try cli.parse()
} catch {
    cli.printUsage(error)
    exit(EX_USAGE)
}

let manager = NSFileManager.defaultManager()
let defaultPath = manager.currentDirectoryPath.stringByAppendingString("/EnvFile.plist")
print(defaultPath)
let resolvedPath = filePath.value != nil ? filePath.value! : defaultPath


if (help.value == true || manager.fileExistsAtPath(resolvedPath) == false) {
    cli.printUsage();
}
else {
    let envFile = EnvFile(envFilePath: resolvedPath)
    var env : Environment? = nil
    if (select.value != nil) {
        env = envFile.environmentWithName(select.value!)
        if (env == nil) {
            NSException(name: NSInternalInconsistencyException, reason:
            "EnvFile does not contain an environment named: " + select.value!, userInfo: nil).raise()
        }
    }
    let configurer = Configurer(envFile: envFile, selectedEnv: env,increment: newVersion.value)
    configurer.configure()
    configurer.printInfo()
}




