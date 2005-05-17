(*
 *  PNG File Format Library
 *  Copyright (c)2005 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)

type grey_bits =
	| GBits1
	| GBits2
	| GBits4
	| GBits8
	| GBits16

type grey_alpha_bits =
	| GABits8
	| GABits16

type true_bits =
	| TBits8
	| TBits16

type index_bits =
	| IBits1
	| IBits2
	| IBits4
	| IBits8

type alpha =
	| NoAlpha
	| HaveAlpha

type color =
	| ClGreyScale of grey_bits
	| ClGreyAlpha of grey_alpha_bits
	| ClTrueColor of true_bits * alpha
	| ClIndexed of index_bits

type header = {
	width : int;
	height : int;
	color : color;
	interlace : bool;
}

type chunk_id = string

type chunk = 
	| CEnd
	| CHeader of header
	| CData of string
	| CPalette of string
	| CUnknown of chunk_id * string

type png = {
	header : header;
	data : string;
	palette : string option;
	chunks : chunk list;
}

type error_msg =
	| Invalid_header
	| Invalid_file
	| Truncated_file
	| Invalid_CRC
	| Invalid_colors
	| Unsupported_colors
	| Invalid_datasize
	| Invalid_filter of int

exception Error of error_msg

let error_msg = function
	| Invalid_header -> "Invalid header"
	| Invalid_file -> "Invalid file"
	| Truncated_file -> "Truncated file"
	| Invalid_CRC -> "Invalid CRC"
	| Invalid_colors -> "Invalid color model"
	| Unsupported_colors -> "Unsupported color model"
	| Invalid_datasize -> "Invalid data size"
	| Invalid_filter f -> "Invalid filter " ^ string_of_int f

let error msg = raise (Error msg)

let is_upper c = ((int_of_char c) land 32) <> 0

let is_critical id = is_upper id.[0]

let is_public id = is_upper id.[1]

let is_reseverd id = is_upper id.[2]

let is_safe_to_copy id = is_upper id.[3]

let is_id_char c =
	(c >= '\065' && c <= '\090') || (c >= '\097' && c <= '\122')

let color_bits = function
	| ClGreyScale g -> (match g with
		| GBits1 -> 1
		| GBits2 -> 2
		| GBits4 -> 4
		| GBits8 -> 8
		| GBits16 -> 16)
	| ClGreyAlpha g -> (match g with
		| GABits8 -> 8
		| GABits16 -> 16)
	| ClTrueColor (t,_) -> (match t with
		| TBits8 -> 8
		| TBits16 -> 16)
	| ClIndexed i -> (match i with
		| IBits1 -> 1
		| IBits2 -> 2
		| IBits4 -> 4
		| IBits8 -> 8)

let crc_table = Array.init 256 (fun n -> 
	let c = ref (Int32.of_int n) in
	for k = 0 to 7 do
		if Int32.logand !c 1l <> 0l then
			c := Int32.logxor 0xEDB88320l (Int32.shift_right_logical !c 1)
		else
			c := (Int32.shift_right_logical !c 1);
	done;
	!c)

let input_crc ch =
	let crc = ref 0xFFFFFFFFl in
	let update c =
		let c = Int32.of_int (int_of_char c) in
		let k = Array.unsafe_get crc_table (Int32.to_int (Int32.logand (Int32.logxor !crc c) 0xFFl)) in
		crc := Int32.logxor k (Int32.shift_right_logical !crc 8)
	in
	let ch2 = IO.create_in
		~read:(fun () ->
			let c = IO.read ch in
			update c;
			c
		)
		~input:(fun s p l ->
			let l = IO.input ch s p l in
			for i = 0 to l - 1 do
				update s.[p+i]
			done;
			l
		)
		~close:(fun () ->
			IO.close_in ch
		)
	in
	ch2 , (fun () -> Int32.logxor !crc 0xFFFFFFFFl)

let parse_header ch =
	let width = IO.BigEndian.read_i32 ch in
	let height = IO.BigEndian.read_i32 ch in
	if width < 0 || height < 0 then error Invalid_header;
	let bits = IO.read_byte ch in
	let color = IO.read_byte ch in
	let color = (match color with
		| 0 -> ClGreyScale (match bits with 1 -> GBits1 | 2 -> GBits2 | 4 -> GBits4 | 8 -> GBits8 | 16 -> GBits16 | _ -> error Invalid_colors)
		| 2 -> ClTrueColor ((match bits with 8 -> TBits8 | 16 -> TBits16 | _ -> error Invalid_colors) , NoAlpha)
		| 3 -> ClIndexed (match bits with 1 -> IBits1 | 2 -> IBits2 | 4 -> IBits4 | 8 -> IBits8 | _ -> error Invalid_colors)
		| 4 -> ClGreyAlpha (match bits with 8 -> GABits8 | 16 -> GABits16 | _ -> error Invalid_colors)
		| 6 -> ClTrueColor ((match bits with 8 -> TBits8 | 16 -> TBits16 | _ -> error Invalid_colors) , HaveAlpha)
		| _ -> error Invalid_colors)
	in
	let compress = IO.read_byte ch in
	let filter = IO.read_byte ch in
	if compress <> 0 || filter <> 0 then error Invalid_header;
	let interlace = IO.read_byte ch in
	let interlace = (match interlace with 0 -> false | 1 -> true | _ -> error Invalid_header) in
	{
		width = width;
		height = height;
		color = color;
		interlace = interlace;
	}

let parse_chunk ch =
	let len = IO.BigEndian.read_i32 ch in
	let ch2 , crc = input_crc ch in
	let id = IO.nread ch2 4 in
	if len < 0 || not (is_id_char id.[0]) || not (is_id_char id.[1]) || not (is_id_char id.[2]) || not (is_id_char id.[3]) then error Invalid_file;
	let data = IO.nread ch2 len in
	let crc_val = IO.BigEndian.read_real_i32 ch in
	if crc_val <> crc() then error Invalid_CRC;
	match id with
	| "IEND" -> CEnd
	| "IHDR" -> CHeader (parse_header (IO.input_string data))
	| "IDAT" -> CData data
	| "PLTE" -> CPalette data
	| _ -> CUnknown (id,data)

let parse ch =
	let sign = (try IO.nread ch 8 with IO.No_more_input -> error Invalid_header) in
	if sign <> "\137\080\078\071\013\010\026\010" then error Invalid_header;
	let rec loop acc =
		match parse_chunk ch with
		| CEnd -> List.rev acc
		| c -> loop (c :: acc)
	in
	let chunks = (try
		loop []
	with
		| IO.No_more_input -> error Truncated_file
		| IO.Overflow _ -> error Invalid_file)
	in
	let header = ref None in
	let data = ref None in
	let pal = ref None in
	List.iter (function
		| CHeader h -> if !header <> None then error Invalid_file; header := Some h
		| CData s -> (match !data with None -> data := Some s | Some s2 -> data := Some (s2 ^ s))
		| CPalette s -> if !pal <> None then error Invalid_file; pal := Some s
		| _ -> ()
	) chunks;
	{
		header = (match !header with None -> error Invalid_file | Some h -> h);
		data = (match !data with None -> error Invalid_file | Some d -> d);
		palette = !pal;
		chunks = chunks;
	}

let filter png data =
	let w = png.header.width in
	let h = png.header.height in
	match png.header.color with
	| ClGreyScale _
	| ClGreyAlpha _
	| ClIndexed _ 
	| ClTrueColor (TBits16,_) -> error Unsupported_colors
	| ClTrueColor (TBits8,alpha) ->
		let alpha = (match alpha with NoAlpha -> false | HaveAlpha -> true) in
		let buf = String.create (w * h * 4) in
		let nbytes = if alpha then 4 else 3 in
		let stride = nbytes * w + 1 in
		if String.length data < h * stride then error Invalid_datasize;
		let bp = ref 0 in
		let get p = int_of_char (String.unsafe_get data p) in
		let bget p = int_of_char (String.unsafe_get buf p) in
		let set v = String.unsafe_set buf !bp (Char.unsafe_chr v); incr bp in
		let filters = [|
			(fun x y v -> v
			);
			(fun x y v -> 
				let v2 = if x = 0 then 0 else bget (!bp - 4) in
				v + v2
			);
			(fun x y v ->
				let v2 = if y = 0 then 0 else bget (!bp - 4*w) in
				v + v2
			);
			(fun x y v ->
				let v2 = if x = 0 then 0 else bget (!bp - 4) in
				let v3 = if y = 0 then 0 else bget (!bp - 4*w) in
				v + (v2 + v3) / 2
			);
			(fun x y v ->
				let a = if x = 0 then 0 else bget (!bp - 4) in
				let b = if y = 0 then 0 else bget (!bp - 4*w) in
				let c = if x = 0 || y = 0 then 0 else bget (!bp - 4 - 4*w) in
				let p = a + b - c in
				let pa = abs (p - a) in
				let pb = abs (p - b) in
				let pc = abs (p - c) in
				let d = (if pa <= pb && pa <= pc then a else if pb <= pc then b else c) in
				v + d
			);
		|] in
		for y = 0 to h - 1 do
			let f = get (y * stride) in
			let f = (if f < 5 then filters.(f) else error (Invalid_filter f)) in
			for x = 0 to w - 1 do
				let p = x * nbytes + y * stride in
				if not alpha then begin
					set 255;
					for c = 1 to 3 do
						let v = get (p + c) in
						set (f x y v)
					done;
				end else begin
					let v = get (p + 4) in
					let a = f x y v in
					set a;
					for c = 1 to 3 do
						let v = get (p + c) in
						set (f x y v)
					done;
				end;
			done;
		done;
		buf