//===- FIRRTLDeclarations.td - FIRRTL declaration ops ------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This describes the MLIR ops for FIRRTL declarations.
//
//===----------------------------------------------------------------------===//

#ifndef CIRCT_DIALECT_FIRRTL_FIRRTLDECLARATIONS_TD
#define CIRCT_DIALECT_FIRRTL_FIRRTLDECLARATIONS_TD

include "FIRRTLAttributes.td"
include "FIRRTLDialect.td"
include "FIRRTLEnums.td"
include "FIRRTLOpInterfaces.td"
include "FIRRTLTypes.td"
include "circt/Dialect/HW/HWOpInterfaces.td"
include "circt/Dialect/HW/HWTypes.td"
include "mlir/IR/OpBase.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/InferTypeOpInterface.td"

class ReferableDeclOp<string mnemonic, list<Trait> traits = []> :
  FIRRTLOp<mnemonic, traits # [HasCustomSSAName,
                               DeclareOpInterfaceMethods<InnerSymbol,["getTargetResultIndex"]>,
                               FNamableOp]> {
}

def InstanceOp : ReferableDeclOp<"instance", [HasParent<"firrtl::FModuleOp, firrtl::WhenOp">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<HWInstanceLike>]> {
  let summary = "Instantiate an instance of a module";
  let description = [{
    This represents an instance of a module.  The results are the modules inputs
    and outputs.  The inputs have flip type, the outputs do not.

    Examples:
    ```mlir
    %0 = firrtl.instance foo @Foo(in io: !firrtl.uint)
    ```
  }];

  let arguments = (ins FlatSymbolRefAttr:$moduleName, StrAttr:$name, NameKindAttr:$nameKind,
                       APIntAttr:$portDirections, StrArrayAttr:$portNames,
                       AnnotationArrayAttr:$annotations,
                       PortAnnotationsAttr:$portAnnotations,
                       UnitAttr:$lowerToBind,
                       OptionalAttr<InnerSymAttr>:$inner_sym);

  let results = (outs Variadic<AnyType>:$results);

  let hasCustomAssemblyFormat = 1;

  let builders = [
    OpBuilder<(ins "::mlir::TypeRange":$resultTypes,
                   "::mlir::StringRef":$moduleName,
                   "::mlir::StringRef":$name,
                   "::circt::firrtl::NameKindEnum":$nameKind,
                   "::mlir::ArrayRef<Direction>":$portDirections,
                   "::mlir::ArrayRef<Attribute>":$portNames,
                   CArg<"ArrayRef<Attribute>", "{}">:$annotations,
                   CArg<"ArrayRef<Attribute>", "{}">:$portAnnotations,
                   CArg<"bool","false">:$lowerToBind,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym)>,
    OpBuilder<(ins "::mlir::TypeRange":$resultTypes,
                   "::mlir::StringRef":$moduleName,
                   "::mlir::StringRef":$name,
                   "::circt::firrtl::NameKindEnum":$nameKind,
                   "::mlir::ArrayRef<Direction>":$portDirections,
                   "::mlir::ArrayRef<Attribute>":$portNames,
                   "ArrayRef<Attribute>":$annotations,
                   "ArrayRef<Attribute>":$portAnnotations,
                   "bool":$lowerToBind,
                   "hw::InnerSymAttr":$inner_sym)>,

    /// Constructor when you have the target module in hand.
    OpBuilder<(ins "FModuleLike":$module,
                   "mlir::StringRef":$name,
                   CArg<"NameKindEnum", "NameKindEnum::DroppableName">:$nameKind,
                   CArg<"ArrayRef<Attribute>", "{}">:$annotations,
                   CArg<"ArrayRef<Attribute>", "{}">:$portAnnotations,
                   CArg<"bool","false">:$lowerToBind,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym)>
  ];

  let extraClassDeclaration = [{
    /// Lookup the module or extmodule for the symbol.  This returns null on
    /// invalid IR.
    FModuleLike getReferencedModule(SymbolTable& symtbl);

    /// Return the port direction for the specified result number.
    Direction getPortDirection(size_t resultNo) {
      return direction::get(getPortDirections()[resultNo]);
    }

    /// Return the port name for the specified result number.
    StringAttr getPortName(size_t resultNo) {
      return getPortNames()[resultNo].cast<StringAttr>();
    }
    StringRef getPortNameStr(size_t resultNo) {
      return getPortName(resultNo).getValue();
    }

    /// Hooks for port annotations.
    ArrayAttr getPortAnnotation(unsigned portIdx);
    void setAllPortAnnotations(ArrayRef<Attribute> annotations);

    /// Builds a new `InstanceOp` with the ports listed in `portIndices` erased,
    /// and updates any users of the remaining ports to point at the new
    /// instance.
    InstanceOp erasePorts(OpBuilder &builder, const llvm::BitVector &portIndices);

    /// Clone the instance op and add ports.  This is usually used in
    /// conjuction with adding ports to the referenced module. This will emit
    /// the new InstanceOp to the same location.
    InstanceOp cloneAndInsertPorts(ArrayRef<std::pair<unsigned, PortInfo>> ports);
  }];
}

def MemOp : ReferableDeclOp<"mem"> {
  let summary = "Define a new mem";
  let arguments =
    (ins ConfinedAttr<I32Attr, [IntMinValue<0>]>:$readLatency,
         ConfinedAttr<I32Attr, [IntMinValue<1>]>:$writeLatency,
         ConfinedAttr<I64Attr, [IntMinValue<1>]>:$depth, RUWAttr:$ruw,
         StrArrayAttr:$portNames, StrAttr:$name, NameKindAttr:$nameKind,
         AnnotationArrayAttr:$annotations,
         PortAnnotationsAttr:$portAnnotations,
         OptionalAttr<InnerSymAttr>:$inner_sym,
         OptionalAttr<MemoryInitAttr>:$init,
         OptionalAttr<StrAttr>:$prefix);
  let results = (outs Variadic<FIRRTLType>:$results);

  let assemblyFormat = [{
    (`sym` $inner_sym^)? `` custom<NameKind>($nameKind)
    $ruw `` custom<MemOp>(attr-dict) `:` qualified(type($results))
  }];

  let builders = [
    OpBuilder<(ins "::mlir::TypeRange":$resultTypes,
                   "uint32_t":$readLatency, "uint32_t":$writeLatency,
                   "uint64_t":$depth, "RUWAttr":$ruw,
                   "ArrayRef<Attribute>":$portNames,
                   CArg<"StringRef", "{}">:$name,
                   CArg<"NameKindEnum", "NameKindEnum::DroppableName">:$nameKind,
                   CArg<"ArrayRef<Attribute>", "{}">:$annotations,
                   CArg<"ArrayRef<Attribute>", "{}">:$portAnnotations,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym)>,
    OpBuilder<(ins "::mlir::TypeRange":$resultTypes, "uint32_t":$readLatency,
                   "uint32_t":$writeLatency, "uint64_t":$depth, "RUWAttr":$ruw,
                   "ArrayRef<Attribute>":$portNames, "StringRef":$name,
                   "NameKindEnum":$nameKind, "ArrayRef<Attribute>":$annotations,
                   "ArrayRef<Attribute>":$portAnnotations,
                   "hw::InnerSymAttr":$inner_sym)>
  ];

  let hasVerifier = 1;

  let hasCanonicalizer = true;

  let extraClassDeclaration = [{
    enum class PortKind { Read, Write, ReadWrite, Debug };

    using NamedPort = std::pair<StringAttr, MemOp::PortKind>;

    /// Return the type of a port given the memory depth, type, and kind
    static FIRRTLType getTypeForPort(uint64_t depth, FIRRTLBaseType dataType,
                                     PortKind portKind, size_t maskBits = 0);

    /// Return the name and kind of ports supported by this memory.
    SmallVector<NamedPort> getPorts();

    /// Return the kind of the specified port.
    PortKind getPortKind(StringRef portName);

    /// Return the kind of the specified port number.
    PortKind getPortKind(size_t resultNo);

    /// Return the data-type field of the memory, the type of each element.
    FIRRTLBaseType getDataType();

    /// Return the number of mask bits.
    size_t getMaskBits();

    /// Return the port name for the specified result number.
    StringAttr getPortName(size_t resultNo);
    StringRef getPortNameStr(size_t resultNo) {
      return getPortName(resultNo).getValue();
    }

    /// Return the port type for the specified result number.
    FIRRTLBaseType getPortType(size_t resultNo);

    // Return the result for this instance that corresponds to the specified
    // port name.
    Value getPortNamed(StringRef name) {
      return getPortNamed(StringAttr::get(getContext(), name));
    }
    Value getPortNamed(StringAttr name);

    /// Hooks for port annotations.
    ArrayAttr getPortAnnotation(unsigned portIdx);
    void setAllPortAnnotations(ArrayRef<Attribute> annotations);

    /// Get the number of read ports, write ports and read write ports.
    void getNumPorts(size_t &numReadPorts, size_t &numWritePorts,
                      size_t &numReadWritePorts, size_t &numDbgsPorts);

    // Extract the relevant attributes from the MemOp and return a FirMemory object.
    FirMemory getSummary();
  }];
}

def NodeOp : ReferableDeclOp<"node", [
      AllTypesMatch<["input","result"]>,
      DeclareOpInterfaceMethods<InferTypeOpInterface, ["inferReturnTypes"]>,
      Forceable]> {
  let summary = "No-op to name a value";
  let description = [{
    A node is simply a named intermediate value in a circuit. The node must
    be initialized to a value with a passive type and cannot be connected to.
    Nodes are often used to split a complicated compound expression into named
    subexpressions.

    ```
      %result = firrtl.node %input : t1
    ```
    }];

  let arguments = (ins PassiveType:$input, StrAttr:$name,
                       NameKindAttr:$nameKind,
                       AnnotationArrayAttr:$annotations,
                       OptionalAttr<InnerSymAttr>:$inner_sym,
                       UnitAttr:$forceable); // ReferenceKinds
  let results = (outs FIRRTLBaseType:$result, Optional<RefType>:$ref);

  let builders = [
    OpBuilder<(ins "::mlir::Value":$input,
                   CArg<"StringRef", "{}">:$name,
                   CArg<"NameKindEnum", "NameKindEnum::DroppableName">:$nameKind,
                   CArg<"ArrayRef<Attribute>", "{}">:$annotations,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym,
                   CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, input, name, nameKind,
                   $_builder.getArrayAttr(annotations),
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable);
    }]>,
    OpBuilder<(ins "::mlir::Value":$input,
                   "StringRef":$name, "NameKindEnum":$nameKind,
                   "::mlir::ArrayAttr":$annotations,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym,
                   CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, input, name, nameKind,
                   annotations,
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable);
    }]>
  ];

  let assemblyFormat = [{
    (`sym` $inner_sym^)? `` custom<NameKind>($nameKind)
    $input (`forceable` $forceable^)? `` custom<FIRRTLImplicitSSAName>(attr-dict) `:` qualified(type($input))
  }];

  let hasCanonicalizer = true;
  let hasFolder = 1;
}

def RegOp : ReferableDeclOp<"reg", [Forceable]> {
  let summary = "Define a new register";
  let description = [{
    Declare a new register:

    ```
    %name = firrtl.reg %clockVal : !firrtl.clock, t1
    ```
    }];

  let arguments = (
    ins ClockType:$clockVal, StrAttr:$name, NameKindAttr:$nameKind,
        AnnotationArrayAttr:$annotations,
        OptionalAttr<InnerSymAttr>:$inner_sym,
        UnitAttr:$forceable);
  let results = (outs AnyRegisterType:$result, Optional<RefType>:$ref);

  let skipDefaultBuilders = true;
  let builders = [
    OpBuilder<(ins "::mlir::TypeRange":$resultTypes, "::mlir::ValueRange":$operands,
                   CArg<"::llvm::ArrayRef<::mlir::NamedAttribute>","{}">:$attributes), [{
      assert(operands.size() == 1u && "mismatched number of parameters");
      odsState.addOperands(operands);
      odsState.addAttributes(attributes);
      assert(resultTypes.size() >= 1u && "mismatched number of return types");
      odsState.addTypes(resultTypes);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType,
                   "::mlir::Value":$clockVal,
                   "::mlir::StringAttr":$name,
                   "::circt::firrtl::NameKindEnumAttr":$nameKind,
                   "::mlir::ArrayAttr":$annotations,
                   "::circt::hw::InnerSymAttr":$inner_sym,
                   "::mlir::UnitAttr":$forceable), [{
      $_state.addOperands(clockVal);
      $_state.addAttribute(getNameAttrName($_state.name), name);
      $_state.addAttribute(getNameKindAttrName($_state.name), nameKind);
      $_state.addAttribute(getAnnotationsAttrName($_state.name), annotations);
      if (inner_sym) {
        $_state.addAttribute(getInnerSymAttrName($_state.name), inner_sym);
      }
      $_state.addTypes(elementType);
      if (forceable) {
        $_state.addAttribute(getForceableAttrName($_state.name), forceable);
        $_state.addTypes(detail::getForceableResultType(true, elementType));
      }
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType,
                   "::mlir::Value":$clockVal,
                   "::llvm::StringRef":$name,
                   "::circt::firrtl::NameKindEnum":$nameKind,
                   "::mlir::ArrayAttr":$annotations,
                   "::circt::hw::InnerSymAttr":$inner_sym,
                   "bool":$forceable), [{
      return build($_builder, $_state, elementType, clockVal,
                   $_builder.getStringAttr(name),
                   ::circt::firrtl::NameKindEnumAttr::get(odsBuilder.getContext(), nameKind),
                   annotations, inner_sym,
                   forceable ? $_builder.getUnitAttr() : nullptr);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType, "::mlir::Value":$clockVal,
                   CArg<"StringRef", "{}">:$name,
                   CArg<"NameKindEnum", "NameKindEnum::DroppableName">:$nameKind,
                   CArg<"ArrayRef<Attribute>","{}">:$annotations,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym,
                   CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, elementType,
                   clockVal, $_builder.getStringAttr(name), nameKind,
                   $_builder.getArrayAttr(annotations),
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType, "::mlir::Value":$clockVal,
                   "StringRef":$name, "NameKindEnum":$nameKind,
                   "::mlir::ArrayAttr":$annotation, "StringAttr":$inner_sym,
                   CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, elementType,
                   clockVal, $_builder.getStringAttr(name), nameKind, annotation,
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable);
    }]>
  ];

  let assemblyFormat = [{
    (`sym` $inner_sym^)? `` custom<NameKind>($nameKind)
    operands (`forceable` $forceable^)? `` custom<FIRRTLImplicitSSAName>(attr-dict) `:` type($clockVal) `,` qualified(type($result)) (`,` qualified(type($ref))^)?

  }];
  let hasCanonicalizeMethod = true;
}

def RegResetOp : ReferableDeclOp<"regreset", [Forceable]> {
  let summary = "Define a new register with a reset";
  let description = [{
    Declare a new register:
    ```
      %name = firrtl.regreset %clockVal, %resetSignal, %resetValue : !firrtl.clock, t1
    ```
    }];

  let arguments = (
    ins ClockType:$clockVal, AnyResetType:$resetSignal,
        AnyRegisterType:$resetValue,
        StrAttr:$name, NameKindAttr:$nameKind,
        AnnotationArrayAttr:$annotations,
        OptionalAttr<InnerSymAttr>:$inner_sym,
        UnitAttr:$forceable);
  let results = (outs AnyRegisterType:$result, Optional<RefType>:$ref);

  let skipDefaultBuilders = true;
  let builders = [
    OpBuilder<(ins "::mlir::TypeRange":$resultTypes, "::mlir::ValueRange":$operands,
                   CArg<"::llvm::ArrayRef<::mlir::NamedAttribute>","{}">:$attributes), [{
      assert(operands.size() == 3u && "mismatched number of parameters");
      odsState.addOperands(operands);
      odsState.addAttributes(attributes);
      assert(resultTypes.size() >= 1u && "mismatched number of return types");
      odsState.addTypes(resultTypes);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType,
                   "::mlir::Value":$clockVal,
                   "::mlir::Value":$resetSignal, "::mlir::Value":$resetValue,
                   "::mlir::StringAttr":$name,
                   "::circt::firrtl::NameKindEnumAttr":$nameKind,
                   "::mlir::ArrayAttr":$annotations,
                   "::circt::hw::InnerSymAttr":$inner_sym,
                   "::mlir::UnitAttr":$forceable), [{
      $_state.addOperands(clockVal);
      odsState.addOperands(resetSignal);
      odsState.addOperands(resetValue);
      $_state.addAttribute(getNameAttrName($_state.name), name);
      $_state.addAttribute(getNameKindAttrName($_state.name), nameKind);
      $_state.addAttribute(getAnnotationsAttrName($_state.name), annotations);
      if (inner_sym) {
        $_state.addAttribute(getInnerSymAttrName($_state.name), inner_sym);
      }
      $_state.addTypes(elementType);
      if (forceable) {
        $_state.addAttribute(getForceableAttrName($_state.name), forceable);
        $_state.addTypes(detail::getForceableResultType(true, elementType));
      }
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType, "::mlir::Value":$clockVal,
                   "::mlir::Value":$resetSignal, "::mlir::Value":$resetValue,
                   CArg<"StringRef", "{}">:$name,
                   CArg<"NameKindEnum", "NameKindEnum::DroppableName">:$nameKind,
                   CArg<"ArrayRef<Attribute>","{}">:$annotations,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym,
                   CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, elementType,
                   clockVal, resetSignal, resetValue,
                   $_builder.getStringAttr(name),
                   ::circt::firrtl::NameKindEnumAttr::get(odsBuilder.getContext(), nameKind),
                   $_builder.getArrayAttr(annotations),
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable ? $_builder.getUnitAttr() : nullptr);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType, "::mlir::Value":$clockVal,
                   "::mlir::Value":$resetSignal, "::mlir::Value":$resetValue,
                   "StringRef":$name, "NameKindEnum":$nameKind,
                    "::mlir::ArrayAttr":$annotation, "StringAttr":$inner_sym,
                    CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, elementType,
                   clockVal, resetSignal, resetValue,
                   $_builder.getStringAttr(name),
                   ::circt::firrtl::NameKindEnumAttr::get(odsBuilder.getContext(), nameKind),
                   annotation,
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable ? $_builder.getUnitAttr() : nullptr);
    }]>
  ];

  let assemblyFormat = [{
    (`sym` $inner_sym^)? `` custom<NameKind>($nameKind)
    operands (`forceable` $forceable^)? `` custom<FIRRTLImplicitSSAName>(attr-dict)
    `:` type($clockVal) `,` qualified(type($resetSignal)) `,` qualified(type($resetValue)) `,` qualified(type($result)) (`,` qualified(type($ref))^)?

  }];

  let hasCanonicalizer = true;
  let hasVerifier = 1;
}

def WireOp : ReferableDeclOp<"wire", [Forceable]> {
  let summary = "Define a new wire";
  let description = [{
    Declare a new wire:
    ```
      %name = firrtl.wire : t1
    ```
    }];

  let arguments = (ins StrAttr:$name, NameKindAttr:$nameKind,
                       AnnotationArrayAttr:$annotations,
                       OptionalAttr<InnerSymAttr>:$inner_sym,
                       UnitAttr:$forceable); // ReferenceKinds
  let results = (outs AnyType:$result, Optional<RefType>:$ref);

  let hasCanonicalizer = true;
  let skipDefaultBuilders = true;

  let builders = [
    OpBuilder<(ins "::mlir::TypeRange":$resultTypes, "::mlir::ValueRange":$operands,
                   CArg<"::llvm::ArrayRef<::mlir::NamedAttribute>","{}">:$attributes), [{
      assert(operands.size() == 0u && "mismatched number of parameters");
      odsState.addOperands(operands);
      odsState.addAttributes(attributes);
      assert(resultTypes.size() >= 1u && "mismatched number of return types");
      odsState.addTypes(resultTypes);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType,
                   "::mlir::StringAttr":$name,
                   "::circt::firrtl::NameKindEnumAttr":$nameKind,
                   "::mlir::ArrayAttr":$annotations,
                   "::circt::hw::InnerSymAttr":$inner_sym,
                   "::mlir::UnitAttr":$forceable), [{
      $_state.addAttribute(getNameAttrName($_state.name), name);
      $_state.addAttribute(getNameKindAttrName($_state.name), nameKind);
      $_state.addAttribute(getAnnotationsAttrName($_state.name), annotations);
      if (inner_sym) {
        $_state.addAttribute(getInnerSymAttrName($_state.name), inner_sym);
      }
      $_state.addTypes(elementType);
      if (forceable) {
        $_state.addAttribute(getForceableAttrName($_state.name), forceable);
        $_state.addTypes(detail::getForceableResultType(true, elementType));
      }
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType,
                   "::llvm::StringRef":$name,
                   "::circt::firrtl::NameKindEnum":$nameKind,
                   "::mlir::ArrayAttr":$annotations,
                   "::circt::hw::InnerSymAttr":$inner_sym,
                   "bool":$forceable), [{
      return build($_builder, $_state, elementType,
                   $_builder.getStringAttr(name),
                   ::circt::firrtl::NameKindEnumAttr::get(odsBuilder.getContext(), nameKind),
                   annotations, inner_sym,
                   forceable ? $_builder.getUnitAttr() : nullptr);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType,
                      CArg<"StringRef", "{}">:$name,
                      CArg<"NameKindEnum", "NameKindEnum::DroppableName">:$nameKind,
                      CArg<"ArrayRef<Attribute>","{}">:$annotations,
                      CArg<"StringAttr", "StringAttr()">:$inner_sym,
                      CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, elementType,
                   name, nameKind,
                   $_builder.getArrayAttr(annotations),
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable);
    }]>,
    OpBuilder<(ins "::mlir::Type":$elementType, "StringRef":$name,
                   "NameKindEnum":$nameKind, "::mlir::ArrayAttr":$annotations,
                   CArg<"StringAttr", "StringAttr()">:$inner_sym,
                   CArg<"bool", "false">:$forceable), [{
      return build($_builder, $_state, elementType,
                   name, nameKind, annotations,
                   inner_sym ? hw::InnerSymAttr::get(inner_sym) : hw::InnerSymAttr(),
                   forceable);
    }]>
  ];

  let assemblyFormat = [{
    (`sym` $inner_sym^)? `` custom<NameKind>($nameKind)
    (`forceable` $forceable^)? `` custom<FIRRTLImplicitSSAName>(attr-dict) `:`
    qualified(type($result)) (`,` qualified(type($ref))^)?
  }];
}

#endif // CIRCT_DIALECT_FIRRTL_FIRRTLDECLARATIONS_TD
