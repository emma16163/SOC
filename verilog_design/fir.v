`timescale 1ns/1ns

module fir
       #(  parameter pADDR_WIDTH = 12,
           parameter pDATA_WIDTH = 32,
           parameter Tape_Num    = 11
        )
       (
           output  wire                     awready,
           output  wire                     wready,
           input   wire                     awvalid,
           input   wire [(pADDR_WIDTH-1):0] awaddr,
           input   wire                     wvalid,
           input   wire [(pDATA_WIDTH-1):0] wdata,
           output  wire                     arready,
           input   wire                     rready,
           input   wire                     arvalid,
           input   wire [(pADDR_WIDTH-1):0] araddr,
           output  wire                     rvalid,
           output  wire [(pDATA_WIDTH-1):0] rdata,
           input   wire                     ss_tvalid,
           input   wire [(pDATA_WIDTH-1):0] ss_tdata,
           input   wire                     ss_tlast,
           output  wire                     ss_tready,
           input   wire                     sm_tready,
           output  wire                     sm_tvalid,
           output  wire [(pDATA_WIDTH-1):0] sm_tdata,
           output  wire                     sm_tlast,

           // bram for tap RAM
           output  wire           [3:0]     tap_WE,
           output  wire                     tap_EN,
           output  wire [(pDATA_WIDTH-1):0] tap_Di,
           output  wire [(pADDR_WIDTH-1):0] tap_A,
           input   wire [(pDATA_WIDTH-1):0] tap_Do,

           // bram for data RAM
           output  wire            [3:0]    data_WE,
           output  wire                     data_EN,
           output  wire [(pDATA_WIDTH-1):0] data_Di,
           output  wire [(pADDR_WIDTH-1):0] data_A,
           input   wire [(pDATA_WIDTH-1):0] data_Do,

           input   wire                     axis_clk,
           input   wire                     axis_rst_n
       );
// write your code here!

// state declare
parameter ap_idle = 0;
parameter ap_start = 1;
parameter ap_done = 2;

reg [1:0] state;

// AXIS_Stream write declare
reg     ss_tready_reg;
reg     ss_finish_reg;
wire    ss_finish;
reg     data_EN_sw_reg;
reg     data_EN_sr_reg;
reg     data_EN_r_d;
wire    stream_prepared;
reg     ap_start_sig;

reg [pADDR_WIDTH-1:0] data_WA_reg;
reg [pDATA_WIDTH-1:0] data_Di_reg;
reg [3:0]             data_WE_reg;
wire[pADDR_WIDTH-1:0] data_WA;

assign data_WE = data_WE_reg ;
assign ss_tready = ss_tready_reg;

assign data_WA = data_WA_reg;
assign data_Di = data_Di_reg;

wire                   ss_write_valid;
wire [3:0]             ss_count;
reg [3:0]              ss_count_reg;
assign ss_count = ss_count_reg;

reg stream_prepared_reg;
assign stream_prepared = stream_prepared_reg;

reg     ss_read_valid_reg;
wire    ss_read_valid;
assign  ss_read_valid = ss_read_valid_reg;

assign  ss_finish = ss_finish_reg;

reg [pADDR_WIDTH-1:0] data_RA_reg;
wire [pADDR_WIDTH-1:0] data_RA;
assign data_RA = data_RA_reg;
assign data_EN = data_EN_sw_reg | data_EN_r_d;

always@(posedge axis_clk)
begin
    data_EN_r_d <= data_EN_sr_reg;
end

assign data_A =(data_EN_sw_reg) ? data_WA :
       (data_EN_sr_reg) ? data_RA : 0;

reg sm_tvalid_reg;
assign sm_tvalid = sm_tvalid_reg;

reg  [pDATA_WIDTH-1:0]  sm_tdata_reg;
assign  sm_tdata = sm_tdata_reg;
reg     sm_tlast_reg;
assign  sm_tlast = sm_tlast_reg;
assign ss_write_valid = ~ ss_read_valid;

reg ctrl_tap_ready_reg;
reg tap_EN_r_d;
reg tap_EN_sr_reg;
wire ctrl_tap_ready;
wire ctrl_tap_valid;
wire ffen;
wire sel;

reg [pADDR_WIDTH-1:0]       tap_RA_sr_reg;
reg [pADDR_WIDTH-1:0]       tap_RA_lr_reg;

wire [pADDR_WIDTH-1:0]      ctrl_tap_addr;
wire [pADDR_WIDTH-1:0]      ctrl_data_addr;

// state
always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        state <= ap_idle;
    end
    else
    begin
        case(state)
            ap_idle:
            begin
                if(ap_start_sig && stream_prepared)
                    state <= ap_start;
                sm_tlast_reg <= 0;
            end

            ap_start:
            begin
                if(ss_finish && sm_tlast)
                    state <= ap_done;

                if(ss_finish  && !ctrl_tap_valid)
                    sm_tlast_reg <= 1;
                else
                    sm_tlast_reg <= 0;
            end
            
        endcase
    end
end

// AXIS_Stream write

always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        ss_tready_reg <= 0;
        ss_finish_reg <= 0;
        ss_count_reg <= 0;
        ss_read_valid_reg <= 0;
        data_WA_reg <= 0;

        stream_prepared_reg <= 0;
        ss_read_valid_reg <= 0;
    end
    else
    begin
        if (!ss_tready && ss_tvalid)
        begin
            case(state)
                ap_idle:
                begin
                    if((ss_count <= Tape_Num - 1) && !stream_prepared)
                    begin
                        data_WE_reg <= 4'b1111;
                        data_EN_sw_reg <= 1;

                        data_WA_reg <= (ss_count == 0) ? 0:data_WA_reg + 4;
                        ss_count_reg <= ss_count_reg + 1;
                        data_Di_reg <= 0;

                    end
                    else
                    begin
                        stream_prepared_reg <= 1;
                        ss_count_reg <= 4'd10;

                        data_EN_sw_reg <= 0;
                        data_WE_reg <= 0;
                    end
                end

                ap_start:
                begin
                    if(ss_write_valid)
                    begin
                        ss_tready_reg <= 1;
                        data_WE_reg <= 4'b1111;
                        data_EN_sw_reg <= 1;

                        data_WA_reg <= (ss_count == 4'd10) ? 0 :data_WA_reg + 4;
                        ss_count_reg <=(ss_count == 4'd10) ? 0 :ss_count_reg + 1;
                        data_Di_reg <= ss_tdata;

                        ss_read_valid_reg <= 1;

                    end
                    else if (sm_tvalid)
                        ss_read_valid_reg <= 0;
                    else
                    begin
                        data_WE_reg <= 0;
                        ss_tready_reg <= 0;

                    end
                end
            endcase
        end
        else
        begin
            data_WE_reg <= 4'b0;
            data_EN_sw_reg <= 0;
            ss_tready_reg <= 0;
            if(ss_tlast)
                ss_finish_reg <= 1;

        end
    end
end

always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        sm_tvalid_reg <= 0;
        ctrl_tap_ready_reg <= 0;
        data_EN_sr_reg <= 0;
        tap_EN_sr_reg <= 0;
    end
    else
    begin
        if (sm_tready && !sm_tvalid)
        begin
            case(state)
                ap_start:
                begin
                    if(ss_read_valid && ctrl_tap_valid)
                    begin
                        sm_tvalid_reg <= 0;
                        data_EN_sr_reg <= 1;
                        tap_EN_sr_reg <= 1;

                        data_RA_reg <= ctrl_data_addr;
                        tap_RA_sr_reg <= ctrl_tap_addr;
                        ctrl_tap_ready_reg <= 1;
                    end
                    else if (ss_read_valid && !ctrl_tap_valid)
                    begin
                        sm_tvalid_reg <= 1;
                        ctrl_tap_ready_reg <= 0 ;

                    end
                end
            endcase
        end
        else
        begin
            sm_tvalid_reg <= 0;
        end
    end
end

//caculate fir declare
reg [pDATA_WIDTH-1:0]       old_ram_data_reg;
reg [pDATA_WIDTH-1:0]       old_cof_data_reg;
wire [pDATA_WIDTH-1:0]      old_ram_data;
wire [pDATA_WIDTH-1:0]      old_cof_data;
wire [pDATA_WIDTH-1:0]      new_ram_data;
wire [pDATA_WIDTH-1:0]      new_cof_data;
wire [3:0] ctrl_count;

assign old_ram_data = old_ram_data_reg;
assign old_cof_data = old_cof_data_reg;

assign new_cof_data = tap_Do;
assign new_ram_data = data_Do;

assign ctrl_tap_ready = ctrl_tap_ready_reg;
assign o_ram_data = sel ?  old_ram_data : new_ram_data;
assign o_cof_data = sel ?  old_cof_data : new_cof_data;

//caculate fir
reg ffen_d;
wire  [pDATA_WIDTH-1:0] o_ram_data;
wire  [pDATA_WIDTH-1:0] o_cof_data;

always@(posedge axis_clk)
begin
    ffen_d <= ffen;

    if(!axis_rst_n)
        sm_tdata_reg <= 0;
    else if(sm_tvalid)
        sm_tdata_reg <= 0;
    else if(ffen_d)
        sm_tdata_reg <= sm_tdata_reg +(o_ram_data*o_cof_data);
end

always@(posedge axis_clk)
begin
    if(ffen)
    begin
        old_ram_data_reg <= new_ram_data;
        old_cof_data_reg <= new_cof_data;
    end
end

// ctrl_tapRAM
wire en;
reg o_valid_reg, ffen_r;
reg [pADDR_WIDTH-1:0] o_data_addr_reg;
reg [pADDR_WIDTH-1:0] o_tap_addr_reg;


assign ctrl_tap_valid = o_valid_reg;
assign ctrl_data_addr = o_data_addr_reg;
assign ctrl_tap_addr = o_tap_addr_reg;
assign ffen = ffen_r;
assign sel = ~ffen ;
assign en = ctrl_tap_ready & ctrl_tap_valid;

reg[3:0] count_reg;
assign ctrl_count = count_reg;

reg [pADDR_WIDTH-1:0]tap_last_addr_reg;

always@(posedge axis_clk)
begin
    if (!axis_rst_n)
    begin
        o_data_addr_reg <= 0;
        o_tap_addr_reg <= 12'd40;
        ffen_r  <= 0;
        o_valid_reg <= 0;
        count_reg <= 0;
    end
    else if(en)
    begin
        o_valid_reg <= (ctrl_count == 4'd11) ? 0 : 1;

        o_data_addr_reg <= (ctrl_count == 4'd11)? 0:o_data_addr_reg + 4;

        o_tap_addr_reg <= (ctrl_count == 4'd11) ? tap_last_addr_reg :
                     (ctrl_tap_addr == 12'd40) ? 0 : ctrl_tap_addr + 4;

        tap_last_addr_reg <= (ctrl_count == 0 && ctrl_tap_addr == 0) ? 12'd40 :
                        (ctrl_count == 0) ? ctrl_tap_addr - 4 : tap_last_addr_reg;

        count_reg <= (ctrl_count == 4'd11) ? 0 :ctrl_count + 1;

        ffen_r  <= 1;
    end
    else
    begin
        o_valid_reg <= 1;
        ffen_r  <= 0;
    end
end

// Lite write declare
reg wready_reg;
reg awready_reg;

reg [pADDR_WIDTH-1:0]       tap_WA_reg;
reg [pDATA_WIDTH-1:0]       tap_Di_reg;
wire [pADDR_WIDTH-1:0]      tap_WA;
reg [pDATA_WIDTH-1:0]       data_length;

assign awready = awready_reg;
assign wready = wready_reg;
assign tap_WE = {4{awready & wready}};

assign tap_WA = tap_WA_reg;
assign tap_Di = tap_Di_reg;

// Lite write
always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        awready_reg <= 0;
        wready_reg <= 0;
        ap_start_sig <= 0;
    end
    else
    begin
        if (!awready && awvalid)
        begin
            if(awaddr>=12'h20 && awaddr<=12'h60)
            begin
                awready_reg <= 1;
                tap_WA_reg <= awaddr-12'h20;
            end
            else
                awready_reg <= 0;
        end
        else
        begin
            awready_reg <= 0;
        end

        if (!wready && wvalid)
        begin
            wready_reg <= 1;
            if(awaddr>=12'h20 && awaddr<=12'h60)
            begin
                tap_Di_reg <= wdata;
            end
            else if (awaddr==12'h10)
                data_length <= wdata;
            else if(awaddr==0 && wdata==1)
                ap_start_sig <= 1;

        end
        else
        begin
            wready_reg <= 0;
            ap_start_sig <= 0;
        end

    end
end

// Lite read declare
reg arready_reg;
reg rvalid_reg;

reg [pDATA_WIDTH-1:0]       rdata_reg;
wire [pADDR_WIDTH-1:0]      tap_RA;

assign arready = arready_reg;
assign rvalid = rvalid_reg;
assign rdata = rdata_reg ;

assign tap_RA = (tap_EN_sr_reg) ? tap_RA_sr_reg : tap_RA_lr_reg;
assign tap_EN = {awready & wready} | tap_EN_r_d ;

always @( posedge axis_clk )
begin
    tap_EN_r_d <= {arvalid & arready} | tap_EN_sr_reg;
end

assign tap_A = ({awready & wready}) ? tap_WA :
       ({arvalid & arready} | tap_EN_sr_reg) ? tap_RA : 0;


// Lite read

always@(*)
begin
    case(state)
        ap_idle:
        begin
            if(araddr==0 && rvalid)
                rdata_reg =32'h04;
            else if(araddr==0 && rvalid && ap_start_sig)
                rdata_reg =32'h01;
            else
                rdata_reg = tap_Do;
        end

        ap_start:
        begin
            if(araddr==0 && rvalid)
                rdata_reg =32'h00;
            else if(awaddr==12'h10 && rvalid)
                rdata_reg = data_length;
            else
                rdata_reg = tap_Do;
        end

        ap_done:
        begin
            if(araddr==0 && rvalid)
                rdata_reg =32'h06;
            else
                rdata_reg = tap_Do;
        end
        default:
            rdata_reg = 0;
    endcase
end

always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        arready_reg <= 0;
        rvalid_reg <= 0;
    end
    else
    begin
        if(!arready && arvalid && !rvalid)
        begin
            if(araddr>=12'h20 && araddr<=12'h60)
            begin
                arready_reg <= 1;
                tap_RA_lr_reg <= araddr-12'h20;
            end
            else if(araddr==0)
            begin
                arready_reg <= 1;
            end
            else if (awaddr==12'h10)
                arready_reg <= 1;
            else
                arready_reg <= 0;

        end
        else if(arready && arvalid && !rvalid)
        begin
            arready_reg <= 0;
            rvalid_reg <= 1;
        end
        else
        begin
            arready_reg <= 0;
            rvalid_reg <= 0;
        end
    end
end
endmodule



