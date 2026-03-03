-- Create a database for project
create database CinemaManagement
use CinemaManagement;


-- A. Create Tables for project
-- 1. Movies
create table Movies(
    movie_id int primary key identity(1, 1),
    title nvarchar(255) not null,
    genre nvarchar(100), 
    duration int not null, -- Minutes (unit)
    release_date Date,
    rating varchar(10), -- Age Limit
    rating_score decimal(3,1), -- Rating Scores
    description nvarchar(max),
    is_active bit default 1
)



-- One room => Many seats
-- 2. Rooms
create table Rooms(
   room_id  int primary key identity(1,1),
   room_name  nvarchar(50) not null,
   screen_type varchar(20), -- 2D, 3D, IMAX
   total_seats int
)

-- 3. Seats 
create table Seats(
    seat_id int primary key identity(1,1),
    room_id int, -- Foreign key on table Rooms
    row_label char(1), -- Row A, B, C, .....
    seat_number  int, -- Number 1, 2, 3, ..... 
    seat_type nvarchar(20) default N'Thường' -- 'Thường', 'Vip', 'Đôi'

    foreign key (room_id) references Rooms(room_id), 


    -- Constraint: In one room, There can't be include 2 seats that get the same label and number
    constraint UC_Room_Seat UNIQUE(room_id, row_label, seat_number)

)


-- 4. Showtimes: combine Movies and Rooms on time flow
create table Showtimes(
    showtime_id  int primary key identity(1,1),
    movie_id int,
    room_id int,
    start_time datetime not null, -- date and time start
    end_time datetime not null, -- date and time end (expected/calculated)
    base_price decimal(10, 2), -- ticket price (haven't include voucher if any

    foreign key (movie_id) references Movies(movie_id),
    foreign key (room_id) references Rooms(room_id)

)

-- 5. Tickets: Booking tickets
create table Tickets(
    ticket_id int primary key identity(1,1),
    showtime_id int,
    seat_id int, 
    customer_name nvarchar(100),
    booking_time datetime  default getdate(),
    status nvarchar(20)  default N'Đã thanh toán', -- Đã thanh toán, Đã hủy
     
    foreign key (showtime_id) references Showtimes(showtime_id),
    foreign key (seat_id) references Seats(seat_id),


    -- Constraint: 1 seat + 1 showtime = just only one tickets
    constraint UC_OneTicketPerSeatAndSHowTime unique(showtime_id, seat_id)
)



-- 6. Concessions: Food (popcorn, soda, snack,...)
create table Concessions(
    item_id int primary key identity(1,1),
    item_name nvarchar(100) not null,
    category nvarchar(50), --Category of food
    price  decimal(10, 2) not null,
    stock_quantity int default 0 -- quantity of food in the stock left

)


-- 7. ConcesssionSales: Food + Tickets Combo (couple, family,....)
create table ConcessionSales(
    sale_id  int primary key identity(1,1),
    ticket_id int, 
    item_id int,
    quantity int default 1,
    total_price decimal(10, 2),

    foreign key (ticket_id) references Tickets(ticket_id),
    foreign key (item_id) references Concessions(item_id)
)


-- Query for Test 1: check number of tables
SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_TYPE = 'BASE TABLE';


-- B. Check Contrainst for Tables
-- Rating Scores must be in the range 0 - 10
alter table Movies
add constraint CHK_Movies_RatingScores
check (rating_score >= 0 and rating_score <= 10);

-- duration of movies must be greater than 0
alter table Movies
add constraint CHK_Movies_Duration
check (duration > 0)


-- Price of ticket must be greater than 0
alter table Showtimes
add constraint CHK_Showtimes_BasePrice
check (base_price > 0)

--Quantity of food in the stock must be greater than or equal 0
alter table Concessions
add constraint CHK_Concessions_Stock
check (stock_quantity >= 0)

-- Price of food must be greater than 0
alter table Concessions
add constraint CHK_Concessions_Price
check (price > 0)


-- Number of combo must be start from 1
alter table ConcessionSales
add constraint CHK_ConcessionSales_Quantity
check (quantity >= 1);

-- Price of combo must be greater than 0
alter table ConcessionSales
add constraint CHK_ConcessionSales_TotalPrice
check (total_price >= 0);


-- -- Ràng buộc logic: ticket_id không được để trống (vì bạn đã chốt Combo = Vé + Food)
alter table ConcessionSales
alter column ticket_id int not null;


-- C. Create some view to report system status
-- 1. View for full information of Showtimes
go -- batch separation
create view View_Movie_Schedule as
select
    s.showtime_id AS [ID],
    m.title AS [Movie],
    r.room_name AS [Room],
    r.screen_type AS [Format],
    s.start_time AS [Start],
    s.base_price AS [Price]
from Showtimes s
inner join Movies m on m.movie_id = s.movie_id
inner join Rooms r on r.room_id = s.room_id;
go --batch separation


-- 2. View for Food Sales details
go -- batch separation
create view View_Food_Sales_Details as
select
    t.ticket_id AS [Mã Vé],
    t.customer_name AS [Tên Khách Hàng],
    c.item_name AS [Tên Món Ăn/Combo],
    cs.quantity AS [Số Lượng],
    cs.total_price AS [Thành Tiền]
from ConcessionSales cs
inner join Tickets t on t.ticket_id = cs.ticket_id
inner join Concessions c on c.item_id = cs.item_id;
go --batch separation


-- D. Stored Procedure (processing functions)
-- 1. Booking Procedure (Automatic Seat Availability Check)
go -- batch separation
create procedure sp_Book_Ticket
    @ShowtimeID  int,
    @SeatID int,
    @CustomerName nvarchar(100)
as
begin
   set nocount on;


   -- Check if anyone take that seat in that Showtime
   if exists (select 1 from Tickets where showtime_id = @ShowtimeID AND seat_id = @SeatID)
    begin
        print N'Lỗi: Ghế này đã có người đặt cho suất chiếu này rồi!';
        rollback transaction;
        return;
    end

    -- If check that seat = null => we can book ticket
    INSERT INTO Tickets (showtime_id, seat_id, customer_name, booking_time, status)
    VALUES (@ShowtimeID, @SeatID, @CustomerName, GETDATE(), N'Đã thanh toán');

    PRINT N'Đặt vé thành công cho khách hàng: ' + @CustomerName;
end 
go -- batch separation

-- 2. Procedure for updating price for many movies
go -- batch separation
create procedure sp_Update_Movie_Price
    @MovieID int,
    @NewPrice decimal(10,2)
as 
begin
    update Showtimes 
    set base_price = @NewPrice
    where movie_id = @MovieID

    print N'Đã cập nhật giá vé mới thành công!';
end;

go -- batch separation


-- 3. Procedure for updating food stock
go -- batch separation
CREATE PROCEDURE sp_Update_Concession_Stock
    @ItemID INT,
    @AddedQuantity INT
AS
BEGIN
    UPDATE Concessions
    SET stock_quantity = stock_quantity + @AddedQuantity
    WHERE item_id = @ItemID;

    PRINT N'Đã nhập thêm hàng vào kho thành công!';
END;
go -- batch separation


-- E. Trigger: for Automation
-------------------------------------------------------------------------------
-- 1. TRIGGER: TRG_CALCULATE_CONCESSION_FINAL_PRICE
-- MỤC TIÊU: Tự động tính tổng tiền và áp dụng chiết khấu Combo 20%.
-- CƠ CHẾ: Kích hoạt ngay sau khi có dữ liệu được Insert hoặc Update vào bảng ConcessionSales.
-------------------------------------------------------------------------------
go
create trigger trg_calculate_concession_final_price
on ConcessionSales
after insert, update
as
begin
    set nocount on;

    -- THỰC HIỆN CẬP NHẬT TỔNG TIỀN (TOTAL_PRICE)
    -- Công thức kinh doanh: [Thành tiền] = [Số lượng] * [Giá bán lẻ niêm yết] * 0.8
    -- Lưu ý: Hệ thống mặc định mọi giao dịch đồ ăn đều đi kèm vé nên được giảm 20%.
    update cs
    set cs.total_price = i.quantity * c.price * 0.8
    from ConcessionSales cs
    inner join inserted i on cs.sale_id = i.sale_id      -- Lấy dữ liệu vừa được nạp vào
    inner join Concessions c on i.item_id = c.item_id;  -- Kết nối với bảng danh mục để lấy đơn giá

    -- Thông báo trạng thái xử lý cho nhân viên vận hành
    print N'hệ thống: đã ghi nhận giao dịch và tự động áp dụng ưu đãi combo (giảm 20%).';
end;
go

-------------------------------------------------------------------------------
-- 2. TRIGGER: TRG_PREVENT_DELETE_MOVIE
-- MỤC TIÊU: Đảm bảo tính toàn vẹn dữ liệu (Referential Integrity).
-- CƠ CHẾ: Chặn hành động XÓA phim nếu phim đó vẫn đang có lịch chiếu trên hệ thống.
-------------------------------------------------------------------------------
go
create trigger trg_prevent_delete_movie
on Movies
instead of delete 
as
begin
    set nocount on;

    -- KIỂM TRA RÀNG BUỘC LỊCH CHIẾU
    -- Nếu ID của bộ phim sắp xóa vẫn tồn tại trong bảng Showtimes (Suất chiếu)
    if exists (
        select 1 
        from Showtimes 
        where movie_id in (select movie_id from deleted)
    )
    begin
        -- Trả về thông báo lỗi và không thực hiện xóa
        print N'lỗi hệ thống: không thể xóa phim này vì hiện đang có suất chiếu hoạt động!';
        print N'gợi ý: vui lòng xóa hoặc dời lịch chiếu trước khi gỡ phim khỏi danh mục.';
    end
    else
    begin
        -- Nếu không vướng lịch chiếu, thực hiện xóa dữ liệu phim
        delete from Movies 
        where movie_id in (select movie_id from deleted);
        
        print N'hệ thống: phim đã được gỡ bỏ thành công khỏi danh sách.';
    end
end;
go