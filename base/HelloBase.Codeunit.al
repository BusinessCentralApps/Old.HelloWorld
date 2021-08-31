codeunit 50130 HelloBase
{
    trigger OnRun()
    begin

    end;

    procedure GetText() returnvalue: Text;
    begin
        returnvalue := 'App Published: xHello World Base!';
    end;
}