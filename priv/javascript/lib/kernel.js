import SpecialForms from './kernel/special_forms';
import Patterns from './patterns/patterns';
import Tuple from './tuple';
import BitString from './bit_string';
import Protocol from './protocol';
import { PID } from './processes/processes';

function tl(list){
  return SpecialForms.list(...list.slice(1));
}

function hd(list){
  return list[0];
}

function is_nil(x){
  return x === null;
}

function is_atom(x){
  return typeof x === 'symbol';
}

function is_binary(x){
  return typeof x === 'string' || x instanceof String;
}

function is_boolean(x){
  return typeof x === 'boolean' || x instanceof Boolean;
}

function is_function(x, arity = -1){
  return typeof x === 'function' || x instanceof Function;
}

function is_float(x){
  return is_number(x) && !Number.isInteger(x);
}

function is_integer(x){
  return Number.isInteger(x);
}

function is_list(x){
  return x instanceof Array;
}

function is_map(x){
  return typeof x === 'object' || x instanceof Object;
}

function is_number(x){
  return typeof x === "number";
}

function is_tuple(x){
  return x instanceof Tuple; 
}

function length(x){
  return x.length;  
}

function is_pid(x){
  return x instanceof PID; 
}

function is_port(x){
  return false;
}

function is_reference(x){
  return false;
}

function is_bitstring(x){
  return is_binary(x) || x instanceof BitString;
}

function __in__(left, right){
  for(let x of right){
    if(match__qmark__(left, x)){
      return true;
    }
  }

  return false; 
}

function abs(number){
  return Math.abs(number);
}

function round(number){
  return Math.round(number);
}

function elem(tuple, index){
  if(is_list(tuple)){
    return tuple[index];
  }

  return tuple.get(index);  
}

function rem(left, right){
  return left % right;  
}

function div(left, right){
  return left / right;  
}

function and(left, right){
  return left && right;  
}

function or(left, right){
  return left || right;
}

function not(arg){
  return !arg;
}

function apply(...args){
  if(args.length === 3){
    let mod = args[0];
    let func = args[1];
    let func_args = args[2];
    return mod[func].apply(null, func_args);
  }else{
    let func = args[0];
    let func_args = args[1];

    return func.apply(null, func_args);
  }
}

function to_string(arg){
  if(is_tuple(arg)){
    return Tuple.to_string(arg);
  }

  return arg.toString();  
}

function match__qmark__(pattern, expr, guard = () => true){
  return Patterns.match_no_throw(pattern, expr, guard) != null;  
}

function defstruct(defaults, values){
  return SpecialForms.map_update(defaults, values);
}

function is_struct_fn(__struct__){
  return function(x){
    return is_map && x[SpecialForms.atom("__struct__")] === __struct__;
  }
}

function defprotocol(spec){
  return new Protocol(spec);
}

function defimpl(protocol, type, impl){
  protocol.implementation(type, impl);
}

export default {
  SpecialForms,
  tl,
  hd,
  is_nil,
  is_atom,
  is_binary,
  is_boolean,
  is_function,
  is_float,
  is_integer,
  is_list,
  is_map,
  is_number,
  is_tuple,
  length,
  is_pid,
  is_port,
  is_reference,
  is_bitstring,
  in: __in__,
  abs,
  round,
  elem,
  rem,
  div,
  and,
  or,
  not,
  apply,
  to_string,
  match__qmark__,
  defstruct,
  is_struct_fn,
  defprotocol,
  defimpl
};


